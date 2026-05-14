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
        print(f"✓ Connecté en tant que {bot.user}")
        print(f"✓ {len(synced)} commandes synchronisées")
    except Exception as e:
        print(f"⚠ Erreur sync : {e}")

# ============ COMMANDES SLASH ============
@bot.tree.command(name="lancer", description="Lance le bot de jeu")
async def lancer(interaction: discord.Interaction):
    if not is_authorized(interaction):
        await interaction.response.send_message("⛔ Non autorisé", ephemeral=True)
        return

    if is_running():
        await interaction.response.send_message("⚠ Le bot tourne déjà")
        return

    try:
        process = subprocess.Popen(BOT_EXE_PATH)
        embed = discord.Embed(
            title="✅ Bot lancé",
            description=f"PID : `{process.pid}`",
            color=0x22c55e,
            timestamp=datetime.now()
        )
        await interaction.response.send_message(embed=embed)
    except Exception as e:
        await interaction.response.send_message(f"❌ Erreur : {e}")

@bot.tree.command(name="stopper", description="Arrête le bot de jeu")
async def stopper(interaction: discord.Interaction):
    if not is_authorized(interaction):
        await interaction.response.send_message("⛔ Non autorisé", ephemeral=True)
        return

    if not is_running():
        await interaction.response.send_message("ℹ Aucun bot en cours")
        return

    subprocess.run(["taskkill", "/F", "/IM", BOT_EXE_NAME], capture_output=True)
    embed = discord.Embed(
        title="🛑 Bot arrêté",
        color=0xef4444,
        timestamp=datetime.now()
    )
    await interaction.response.send_message(embed=embed)

@bot.tree.command(name="statut", description="État du bot")
async def statut(interaction: discord.Interaction):
    if not is_authorized(interaction):
        await interaction.response.send_message("⛔ Non autorisé", ephemeral=True)
        return

    running = is_running()
    embed = discord.Embed(
        title="📊 Statut du bot",
        description="🟢 En cours" if running else "🔴 Arrêté",
        color=0x22c55e if running else 0x6b7280,
        timestamp=datetime.now()
    )
    await interaction.response.send_message(embed=embed)

# ============ LANCEMENT ============
if __name__ == "__main__":
    Path("logs").mkdir(exist_ok=True)
    bot.run(TOKEN)