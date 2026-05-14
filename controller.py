import os
import subprocess
from datetime import datetime
from pathlib import Path

import discord
from discord.ext import commands
from dotenv import load_dotenv

# ============ CONFIG ============
load_dotenv()
TOKEN = os.getenv("DISCORD_TOKEN")
AUTHORIZED_USER_ID = int(os.getenv("AUTHORIZED_USER_ID"))
BOT_EXE_PATH = os.getenv("BOT_EXE_PATH")
BOT_EXE_NAME = Path(BOT_EXE_PATH).name

# ============ SETUP ============
intents = discord.Intents.default()
intents.message_content = True
bot = commands.Bot(command_prefix="!", intents=intents)

# ============ HELPERS ============
def is_authorized(interaction: discord.Interaction) -> bool:
    return interaction.user.id == AUTHORIZED_USER_ID

def is_running() -> bool:
    result = subprocess.run(
        ["tasklist", "/FI", f"IMAGENAME eq {BOT_EXE_NAME}"],
        capture_output=True, text=True
    )
    return BOT_EXE_NAME.lower() in result.stdout.lower()

# ============ EVENTS ============
@bot.event
async def on_ready():
    try:
        synced = await bot.tree.sync()
        print(f"✓ Connected as {bot.user}")
        print(f"✓ {len(synced)} commands synced")
    except Exception as e:
        print(f"⚠ Sync error: {e}")

# ============ SLASH COMMANDS ============
@bot.tree.command(name="start", description="Start the game bot")
async def start(interaction: discord.Interaction):
    if not is_authorized(interaction):
        await interaction.response.send_message("⛔ Unauthorized", ephemeral=True)
        return

    if is_running():
        await interaction.response.send_message("⚠ The bot is already running")
        return

    try:
        process = subprocess.Popen(BOT_EXE_PATH)
        embed = discord.Embed(
            title="✅ Bot started",
            description=f"PID: `{process.pid}`",
            color=0x22c55e,
            timestamp=datetime.now()
        )
        await interaction.response.send_message(embed=embed)
    except Exception as e:
        await interaction.response.send_message(f"❌ Error: {e}")

@bot.tree.command(name="stop", description="Stop the game bot")
async def stop(interaction: discord.Interaction):
    if not is_authorized(interaction):
        await interaction.response.send_message("⛔ Unauthorized", ephemeral=True)
        return

    if not is_running():
        await interaction.response.send_message("ℹ No bot running")
        return

    subprocess.run(["taskkill", "/F", "/IM", BOT_EXE_NAME], capture_output=True)
    embed = discord.Embed(
        title="🛑 Bot stopped",
        color=0xef4444,
        timestamp=datetime.now()
    )
    await interaction.response.send_message(embed=embed)

@bot.tree.command(name="status", description="Bot status")
async def status(interaction: discord.Interaction):
    if not is_authorized(interaction):
        await interaction.response.send_message("⛔ Unauthorized", ephemeral=True)
        return

    running = is_running()
    embed = discord.Embed(
        title="📊 Bot status",
        description="🟢 Running" if running else "🔴 Stopped",
        color=0x22c55e if running else 0x6b7280,
        timestamp=datetime.now()
    )
    await interaction.response.send_message(embed=embed)

# ============ STARTUP ============
if __name__ == "__main__":
    Path("logs").mkdir(exist_ok=True)
    bot.run(TOKEN)
