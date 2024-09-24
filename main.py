import discord
from discord.ext import commands
import configparser
import os
import asyncio

# Define paths
current_directory = os.path.dirname(os.path.abspath(__file__))
config_file = os.path.join(current_directory, 'config.ini')


# Load configuration
def load_config():
    config = configparser.ConfigParser()
    config.read(config_file)
    return config['BOT']['discord_secret']

# Get Discord secret from config file
discord_secret = load_config()

# Intents (required for some features)
intents = discord.Intents.default()
intents.message_content = True  # Ensure you have this enabled if you want to listen to message content

# Bot setup
bot = commands.Bot(command_prefix='!', intents=intents)

# Load cogs
async def load_cogs():
    cogs_directory = os.path.join(current_directory, 'cogs')
    for filename in os.listdir(cogs_directory):
        if filename.endswith('.py'):
            await bot.load_extension(f'cogs.{filename[:-3]}')

# On ready event
@bot.event
async def on_ready():
    print(f'Logged in as {bot.user}')

# Run the bot
async def main():
    await load_cogs()  # Load cogs before starting the bot
    try:
        await bot.start(discord_secret)
    except discord.errors.LoginFailure:
        print("Failed to login. Please check your Discord token in the config file and try again.")

# Start the bot
asyncio.run(main())