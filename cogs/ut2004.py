import discord
from discord.ext import commands
import socket
import threading
import json
import configparser
import asyncio
import random
import time


class UT2004Cog(commands.Cog):
    def __init__(self, bot):
        self.bot = bot

        # Load configuration from the parent directory
        self.config = configparser.ConfigParser()
        self.config.read('config.ini')

        self.channel_id = int(self.config['Discord']['channel_id'])  # Load channel ID from config
        self.host = self.config['Server']['host']  # Load host from config
        self.port = int(self.config['Server']['port'])  # Load port from config

        self.socket_server = (self.host, self.port)  # Socket server address
        self.user_colors = {}  # Dictionary to store usernames and their assigned colors

        # Cache for tracking recently sent "Say" messages
        self.recent_say_messages = set()  # Cache for "Say" messages
        self.cache_limit = 100  # Set a limit for cache size to avoid excessive memory usage

        # Persistent socket connection
        self.conn = None
        self.socket_thread = None
        self.stop_socket_thread = threading.Event()  # Event to signal stopping the thread

        self.start_socket_thread()

    def cog_unload(self):
        """Ensure proper closure of the socket connection and thread."""
        self.stop_socket_thread.set()  # Signal the socket thread to stop
        if self.conn:
            self.conn.close()  # Close the socket connection
        if self.socket_thread:
            self.socket_thread.join()  # Wait for the socket thread to cleanly exit

    def start_socket_thread(self):
        """Starts a new socket thread if one isn't already running."""
        if not self.socket_thread or not self.socket_thread.is_alive():
            self.stop_socket_thread.clear()  # Reset stop event
            self.socket_thread = threading.Thread(target=self.start_socket_server, daemon=True)
            self.socket_thread.start()  # Start the socket server in a separate thread

    def start_socket_server(self):
        """Start the socket server to receive messages."""
        while not self.stop_socket_thread.is_set():  # Check for stop event
            try:
                s = socket.create_server(self.socket_server)
                print("Socket server started, waiting for a connection...")
                conn, addr = s.accept()
                print(f"Connected to {addr}")
                self.conn = conn  # Store the persistent connection

                with conn:
                    while not self.stop_socket_thread.is_set():  # Keep running until stopped
                        try:
                            msg_buf = conn.recv(255)
                            if msg_buf:
                                u_msg = msg_buf.decode("utf-8").strip()
                                print(f"Received from socket: {u_msg}")

                                # Split the incoming message into individual JSON objects
                                messages = u_msg.split('\0')

                                for message in messages:
                                    if message:
                                        try:
                                            message_data = json.loads(message)

                                            # Check for ServerTravel message
                                            if message_data.get("type") == "ServerTravel":
                                                print("ServerTravel message received. Disconnecting...")
                                                self.conn.close()  # Close the current connection
                                                self.conn = None  # Reset the connection variable
                                                asyncio.run_coroutine_threadsafe(self.reconnect_socket(), self.bot.loop)
                                                return  # Exit the loop to stop processing further messages

                                            # Forward the message to Discord
                                            asyncio.run_coroutine_threadsafe(self.forward_to_discord(message_data), self.bot.loop)

                                        except json.JSONDecodeError as e:
                                            print(f"Failed to parse JSON: {e}")
                        except Exception as e:
                            print(f"Socket error: {e}")
                            break

            except Exception as e:
                print(f"Failed to start socket server: {e}")
                print("Retrying in 5 seconds...")
                time.sleep(5)  # Wait before retrying to establish the socket server

    async def reconnect_socket(self):
        """Reconnect to the socket server after 20 seconds."""
        await asyncio.sleep(20)  # Wait for 20 seconds
        if not self.stop_socket_thread.is_set():  # Only reconnect if not stopping
            print("Attempting to reconnect to the socket server...")
            self.start_socket_thread()  # Restart the socket server in a new thread

    def get_message_id(self, username, msg):
        """Generate a unique identifier for each message."""
        return hash((username, msg))

    def get_color_by_team(self, team_index, username=None):
        """Get color based on team index; random color for unassigned usernames."""
        if team_index == "0":  # Team 0 (Red)
            return discord.Color.red()
        elif team_index == "1":  # Team 1 (Blue)
            return discord.Color.blue()
        else:  # No team or other values
            if username and username not in self.user_colors:
                self.user_colors[username] = self.get_random_color()
            return self.user_colors.get(username, discord.Color.dark_gray())  # Default color if no team info

    async def forward_to_discord(self, message_data):
        """Forwards a chat or kill message from the socket server to Discord."""
        if message_data.get("type") == "Say":
            username = message_data.get("sender")
            msg = message_data.get("msg")
            team_index = message_data.get("teamIndex", "-1")  # Default to -1 if not provided

            # Generate a unique message ID for "Say" messages
            message_id = self.get_message_id(username, msg)

            # Avoid duplicate "Say" messages by checking the cache
            if message_id in self.recent_say_messages:
                print(f"Duplicate Say message detected, skipping: {username}: {msg}")
                return

            # If not a duplicate, add to cache and enforce the limit
            self.recent_say_messages.add(message_id)
            if len(self.recent_say_messages) > self.cache_limit:
                self.recent_say_messages.pop()

            # Assign color based on the team index
            color = self.get_color_by_team(team_index, username)

            # Create an embed to colorize the username
            embed = discord.Embed(description=f"**{username}:** {msg}", color=color)

            channel = self.bot.get_channel(self.channel_id)
            if channel:
                try:
                    await channel.send(embed=embed)  # Send the message to the Discord channel
                    print(f"Message sent to Discord: {username}: {msg}")
                except Exception as e:
                    print(f"Failed to send message to Discord: {e}")
            else:
                print(f"Channel with ID {self.channel_id} not found.")

        elif message_data.get("type") == "Kill":
            # Handle death/kill messages
            game_event = message_data.get("sender", "Game")
            msg = message_data.get("msg")
            team_index = message_data.get("teamIndex", "-1")  # Default to -1 if not provided

            # Send kill message without duplicate checking
            color = self.get_color_by_team(team_index)

            # Create an embed for the kill event
            embed = discord.Embed(description=f"**{msg}**", color=color)

            channel = self.bot.get_channel(self.channel_id)
            if channel:
                try:
                    await channel.send(embed=embed)  # Send the kill message to the Discord channel
                    print(f"Kill event sent to Discord: {msg}")
                except Exception as e:
                    print(f"Failed to send kill event to Discord: {e}")
            else:
                print(f"Channel with ID {self.channel_id} not found.")

        elif message_data.get("type") == "FlagCap":
            # Handle flag capture messages
            msg = message_data.get("msg")
            team_index = message_data.get("teamIndex", "-1")  # Default to -1 if not provided

            # Send flag capture message without duplicate checking
            color = self.get_color_by_team(team_index)

            # Create an embed for the flag capture event
            embed = discord.Embed(description=f"**Flag Capture:** {msg}", color=color)

            channel = self.bot.get_channel(self.channel_id)
            if channel:
                try:
                    await channel.send(embed=embed)  # Send the flag capture message to the Discord channel
                    print(f"Flag capture event sent to Discord: {msg}")
                except Exception as e:
                    print(f"Failed to send flag capture event to Discord: {e}")
            else:
                print(f"Channel with ID {self.channel_id} not found.")

        elif message_data.get("type") == "MatchEnd":
            # Handle match end messages
            winner_team = message_data.get("sender")  # This will be "Red" or "Blue"
            msg = message_data.get("msg")
            team_index = message_data.get("teamIndex")  # Get the team index from the message

            # Get the color based on the winning team's index
            color = self.get_color_by_team(team_index)

            # Create an embed for the match end event
            embed = discord.Embed(description=f"**Match Over!** {msg}", color=color)

            channel = self.bot.get_channel(self.channel_id)
            if channel:
                try:
                    await channel.send(embed=embed)  # Send the match end message to the Discord channel
                    print(f"Match end event sent to Discord: {msg}")
                except Exception as e:
                    print(f"Failed to send match end event to Discord: {e}")
            else:
                print(f"Channel with ID {self.channel_id} not found.")

    async def send_message_to_socket(self, username, message_content):
        """Sends a message to the socket server."""
        if not self.conn:
            print("No socket connection available. Cannot send the message.")
            return

        try:
            # Construct the message in the required format
            msg = '{"type":"Say","sender":"' + username + '","msg":"' + message_content + '"}\0'

            # Send the message to the socket server using the persistent connection
            self.conn.sendall(msg.encode('utf-8'))
            print(f"Sent to socket server: {username}: {message_content}")
        except BrokenPipeError:
            print("Connection lost. Cannot send message.")
            self.conn = None  # Reset connection to indicate that it's lost
        except Exception as e:
            print(f"Failed to send message to socket: {e}")

    @commands.Cog.listener()
    async def on_message(self, message):
        """Forwards messages from Discord to the socket server."""
        if message.channel.id == self.channel_id and not message.author.bot:
            if not message.content.startswith("Discord: "):
                # Call the updated send_message_to_socket function with username and message
                await self.send_message_to_socket(message.author.name, message.content)

    def get_random_color(self):
        """Generate a random color for usernames."""
        return discord.Color(random.randint(0x000000, 0xFFFFFF))


async def setup(bot):
    await bot.add_cog(UT2004Cog(bot))
