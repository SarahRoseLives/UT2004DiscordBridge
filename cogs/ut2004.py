import discord
from discord.ext import commands, tasks
import aiohttp
from bs4 import BeautifulSoup
import configparser
import os


class UT2004Cog(commands.Cog):
    def __init__(self, bot):
        self.bot = bot

        # Load configuration from the parent directory
        self.config = configparser.ConfigParser()

        self.config.read('config.ini')


        self.channel_id = int(self.config['Discord']['channel_id'])  # Load channel ID from config
        self.username = self.config['Server']['user']  # Load username from config
        self.password = self.config['Server']['pass']  # Load password from config
        self.url = f"http://{self.config['Server']['host']}:{self.config['Server']['port']}/ServerAdmin/current_console_log#END"

        self.seen_messages = set()  # Set to track all seen messages
        self.initialized = False  # Flag to indicate the first run
        self.check_chat_messages.start()  # Start the background task

    def cog_unload(self):
        self.check_chat_messages.stop()  # Stop the background task when cog is unloaded

    @tasks.loop(seconds=2)  # Adjust the frequency as needed
    async def check_chat_messages(self):
        async with aiohttp.ClientSession() as session:
            async with session.get(self.url, auth=aiohttp.BasicAuth(self.username, self.password)) as response:
                if response.status == 200:
                    html_content = await response.text()
                    chat_messages = self.get_chat_messages(html_content)

                    if not self.initialized:
                        self.seen_messages.update(chat_messages)  # Add all messages to seen_messages
                        self.initialized = True  # Mark that initialization is done
                    else:
                        # Check for new messages that haven't been seen yet
                        for chat_message in chat_messages:
                            clean_message = chat_message.replace("\xa0", " ").strip()  # Normalize message

                            # Add new messages to Discord and seen_messages
                            if clean_message not in self.seen_messages:
                                await self.forward_to_discord(clean_message)  # Forward new message to Discord
                                self.seen_messages.add(clean_message)  # Add the new message to seen_messages
                            else:
                                print(f"Duplicate message detected, skipping: {clean_message}")  # Debugging line
                else:
                    print(f"Failed to retrieve the page. Status code: {response.status}")

    def get_chat_messages(self, html_content):
        soup = BeautifulSoup(html_content, 'html.parser')
        raw_log = soup.get_text(separator="\n", strip=True)
        lines = raw_log.split("\n")

        chat_messages = []
        for line in lines:
            line = line.strip()
            if line.startswith(">"):
                chat_message = line[1:].strip()  # Removes ">" and any leading spaces
                if chat_message and ":" in chat_message:
                    chat_messages.append(chat_message)  # Add only messages with ":"

        print(f"Retrieved chat messages: {chat_messages}")  # Debugging line
        return chat_messages

    async def forward_to_discord(self, chat_message):
        # Ignore messages that start with "Discord: "
        if chat_message.startswith("Discord: "):
            return
        if "None" in chat_message:
            return

        channel = self.bot.get_channel(self.channel_id)
        if channel:
            try:
                await channel.send(chat_message)  # Send the message to the Discord channel
                print(f"Message sent to Discord: {chat_message}")  # Debugging line
            except Exception as e:
                print(f"Failed to send message to Discord: {e}")  # Error handling for send failures
        else:
            print(f"Channel with ID {self.channel_id} not found.")  # Error handling if channel is not found

    @commands.Cog.listener()
    async def on_message(self, message):
        """Forwards messages from Discord to the game server."""
        if message.channel.id == self.channel_id and not message.author.bot:
            # Prevent echoing messages sent by the bot itself
            if not message.content.startswith("Discord: "):
                # Forward message to the chat server with "Discord: " prefix
                await self.send_message_to_chat_server(f'Discord: {message.author}: {message.content}')

    async def send_message_to_chat_server(self, message_content):
        """Sends a message to the game server."""
        data = {
            "SendText": f"say {message_content}",  # Format the message to send to the server
            "Send": "Send"  # This is the submit button's value
        }

        url = f"http://{self.config['Server']['host']}:{self.config['Server']['port']}/ServerAdmin/current_console"  # Change this if needed
        async with aiohttp.ClientSession() as session:
            async with session.post(url, auth=aiohttp.BasicAuth(self.username, self.password), data=data) as response:
                if response.status == 200:
                    print("Message sent to the game server successfully!")
                else:
                    print(f"Failed to send message. Status code: {response.status}")


async def setup(bot):
    await bot.add_cog(UT2004Cog(bot))
