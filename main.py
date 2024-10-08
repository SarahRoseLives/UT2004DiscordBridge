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

    # Check if the config file exists
    if not os.path.isfile(config_file):
        # If not, create a new config file with default settings
        config['BOT'] = {'discord_secret': ''}
        config['Discord'] = {'channel_id': ''}
        config['Server'] = {
            'host': 'localhost',
            'port': '49321'
        }

        with open(config_file, 'w') as configfile:
            config.write(configfile)
            print(f"Created a new config file at: {config_file}")

    # Read the config file
    config.read(config_file)

    # Return the discord_secret
    return config['BOT']['discord_secret']


# Example usage
discord_secret = load_config()
print(f"Discord Secret: {discord_secret}")

# Intents (required for some features)
intents = discord.Intents.default()
intents.message_content = True  # Ensure you have this enabled if you want to listen to message content

# Bot setup
class MyBot(commands.Bot):
    async def setup_hook(self):
        cogs_directory = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'cogs')
        for filename in os.listdir(cogs_directory):
            if filename.endswith('.py'):
                await self.load_extension(f'cogs.{filename[:-3]}')

bot = MyBot(command_prefix='!', intents=intents)

# On ready event
@bot.event
async def on_ready():
    print(f'Logged in as {bot.user}')

# Run the bot
async def main():
    try:
        await bot.start(discord_secret)
    except discord.errors.LoginFailure:
        print("Failed to login. Please check your Discord token in the config file and try again.")

# Start the bot
asyncio.run(main())