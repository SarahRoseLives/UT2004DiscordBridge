import discord
from discord.ext import commands
import socket
import threading
import json
import configparser
import asyncio
import random

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

        # Cache for tracking recently sent messages
        self.recent_messages = set()  # Use a set to store message IDs (or hashes)
        self.cache_limit = 100  # Set a limit for cache size to avoid excessive memory usage

        # Persistent socket connection
        self.conn = None
        self.pong_received = True  # Assume PONG is received initially
        self.socket_thread = threading.Thread(target=self.start_socket_server, daemon=True)
        self.socket_thread.start()  # Start the socket server in a separate thread

        # Start the PING loop
        self.bot.loop.create_task(self.ping_heartbeat())

    def cog_unload(self):
        """Clean up when the cog is unloaded."""
        if self.conn:
            self.conn.close()

    async def ping_heartbeat(self):
        """Send a PING message every 10 seconds and listen for PONG."""
        while True:
            if self.conn:
                ping_msg = '{"type":"Heartbeat","sender":"Discord","msg":"PING"}\0'
                try:
                    self.conn.sendall(ping_msg.encode('utf-8'))
                    print("Sent PING to socket server.")
                except Exception as e:
                    print(f"Failed to send PING: {e}")

                # Wait for 10 seconds to receive PONG
                await asyncio.sleep(10)

                # If no PONG received, assume socket server has restarted
                if not self.pong_received:
                    print("No PONG response received. Attempting to reconnect...")
                    await self.reconnect_socket()
                    self.pong_received = True  # Reset flag

            await asyncio.sleep(10)  # Wait for 10 seconds before sending the next PING

    def start_socket_server(self):
        """Start the socket server to receive messages."""
        s = socket.create_server(self.socket_server)

        while True:
            print("Waiting for a connection...")
            conn, addr = s.accept()
            print(f"Connected to {addr}")
            self.conn = conn  # Store the persistent connection

            with conn:
                while True:
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

                                        # Check for PONG response
                                        if message_data.get("type") == "Heartbeat" and message_data.get("msg") == "PONG":
                                            print("Received PONG from socket server.")
                                            self.pong_received = True  # Set flag to indicate PONG received

                                        # Forward the message to Discord
                                        asyncio.run_coroutine_threadsafe(self.forward_to_discord(message_data), self.bot.loop)
                                    except json.JSONDecodeError as e:
                                        print(f"Failed to parse JSON: {e}")
                    except Exception as e:
                        print(f"Socket error: {e}")
                        break

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
        # Check if the message is a chat ("Say") or a kill event ("Kill") or flag capture ("FlagCap")
        if message_data.get("type") == "Say":
            username = message_data.get("sender")
            msg = message_data.get("msg")
            team_index = message_data.get("teamIndex", "-1")  # Default to -1 if not provided

            # Generate a unique message ID
            message_id = self.get_message_id(username, msg)

            # Avoid duplicate messages by checking the cache
            if message_id in self.recent_messages:
                print(f"Duplicate message detected, skipping: {username}: {msg}")
                return

            # If not a duplicate, add to cache and enforce the limit
            self.recent_messages.add(message_id)
            if len(self.recent_messages) > self.cache_limit:
                self.recent_messages.pop()

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

            # Generate a unique message ID for the kill event
            message_id = self.get_message_id(game_event, msg)

            # Avoid duplicate messages by checking the cache
            if message_id in self.recent_messages:
                print(f"Duplicate kill message detected, skipping: {msg}")
                return

            # If not a duplicate, add to cache and enforce the limit
            self.recent_messages.add(message_id)
            if len(self.recent_messages) > self.cache_limit:
                self.recent_messages.pop()

            # Assign color based on the team index, similar to "Say" messages
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

            # Generate a unique message ID for the flag capture event
            message_id = self.get_message_id("FlagCap", msg)

            # Avoid duplicate messages by checking the cache
            if message_id in self.recent_messages:
                print(f"Duplicate flag capture message detected, skipping: {msg}")
                return

            # If not a duplicate, add to cache and enforce the limit
            self.recent_messages.add(message_id)
            if len(self.recent_messages) > self.cache_limit:
                self.recent_messages.pop()

            # Assign color based on the team index
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

    async def reconnect_socket(self):
        """Attempt to reconnect to the socket server."""
        for attempt in range(5):  # Try to reconnect 5 times
            try:
                print(f"Attempting to reconnect... ({attempt + 1}/5)")
                s = socket.create_connection(self.socket_server)
                self.conn = s
                print("Reconnection successful!")
                return
            except Exception as e:
                print(f"Reconnection failed: {e}")
                await asyncio.sleep(5)  # Wait before trying again

    async def send_message_to_socket(self, username, message_content):
        """Sends a message to the socket server."""
        if not self.conn:
            print("No socket connection available. Attempting to reconnect...")
            await self.reconnect_socket()

        if not self.conn:
            print("Reconnection failed. Could not send the message.")
            return

        try:
            # Construct the message in the required format
            msg = f'{{"type":"Say","sender":"{username}","msg":"{message_content}"}}\0'
            print(f"Sending message to socket server: {msg}")

            # Send the message to the socket server using the persistent connection
            self.conn.sendall(msg.encode('utf-8'))
            print(f"Sent to socket server: {username}: {message_content}")
        except BrokenPipeError:
            print("Connection lost, attempting to reconnect...")
            self.conn = None  # Reset connection to force a reconnect next time
            await self.reconnect_socket()  # Attempt reconnection
        except Exception as e:
            print(f"Failed to send message to socket: {e}")

    @commands.Cog.listener()
    async def on_message(self, message):
        """Forwards messages from Discord to the socket server."""
        if message.channel.id == self.channel_id and not message.author.bot:
            print(f"Received message from Discord: {message.author.name}: {message.content}")  # Debug line
            if not message.content.startswith("Discord: "):
                await self.send_message_to_socket(message.author.name, message.content)

    def get_random_color(self):
        """Generate a random color for usernames."""
        return discord.Color(random.randint(0x000000, 0xFFFFFF))


async def setup(bot):
    await bot.add_cog(UT2004Cog(bot))
