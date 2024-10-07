class DiscordBridge extends Mutator config(DiscordBridge);

var config string discord_bridge_addr;
var config int discord_bridge_port;
var config bool bBridgeSay;
var config bool bBridgeTeamSay;
var config bool bBridgeKills;
var config bool bBridgeFlagCaps;
var config int  chatR;
var config int  chatG;
var config int  chatB;

var DiscordBridgeLink discordLink;
var DiscordBridgeBroadcastHandler chatHandler;

simulated function PreBeginPlay()
{
    if (Role!=ROLE_Authority)
    {
        return;
    }

    //Spawn the DiscordBridgeLink
    discordLink = Spawn(class'DiscordBridgeLink');
    discordLink.Init(self,discord_bridge_addr,discord_bridge_port);

    //Spawn the DiscordBridgeBroadcastHandler
    chatHandler = Spawn(class'DiscordBridgeBroadcastHandler');
    chatHandler.Init(self);
    Level.Game.BroadcastHandler.RegisterBroadcastHandler(chatHandler);
}

//This really makes sure the old discordLink is gone, since it seems like it used to kind of persist (despite being transient)
//which prevented the client from sending messages to the right one.  This was an issue I noticed with my Crowd Control mutator
function ServerTraveling(string URL, bool bItems)
{
    if (discordLink!=None){
        discordLink.Close();
        discordLink.Destroy();
        discordLink=None;
    }

    Super.ServerTraveling(URL,bItems);
}


static function FillPlayInfo(PlayInfo PlayInfo) {
    Super.FillPlayInfo(PlayInfo);  // Always begin with calling parent
    
    PlayInfo.AddSetting("Discord Bridge", "discord_bridge_addr", "Discord Bridge Address", 0, 2, "Text","50");
    PlayInfo.AddSetting("Discord Bridge", "discord_bridge_port", "Discord Bridge Port", 0, 2, "Text","5;49152:65535");
    PlayInfo.AddSetting("Discord Bridge", "bBridgeSay", "Bridge Regular Messages to Discord", 0, 1, "Check");
    PlayInfo.AddSetting("Discord Bridge", "bBridgeTeamSay", "Bridge Team Messages to Discord", 0, 1, "Check");
    PlayInfo.AddSetting("Discord Bridge", "bBridgeKills", "Bridge Kills to Discord", 0, 1, "Check");
    PlayInfo.AddSetting("Discord Bridge", "bBridgeFlagCaps", "Bridge Flag Captures to Discord", 0, 1, "Check");
    PlayInfo.AddSetting("Discord Bridge", "chatR", "Discord Chat Red", 0, 2, "Text","3;1:255");
    PlayInfo.AddSetting("Discord Bridge", "chatG", "Discord Chat Green", 0, 2, "Text","3;1:255");
    PlayInfo.AddSetting("Discord Bridge", "chatB", "Discord Chat Blue", 0, 2, "Text","3;1:255");

}

//Ascii character 27, followed by an ascii character containing the R, G, and B values
//range 1-255 (as far as I can tell) for each
function string GenerateRGBTextCode(int r, int g, int b)
{
    if (r<=0) r=1;
    if (g<=0) g=1;
    if (b<=0) b=1;

    if (r>255) r=255;
    if (g>255) g=255;
    if (b>255) b=255;

    return chr(27)$chr(r)$chr(g)$chr(b);
}

function ReceiveMsgFromDiscord(string MsgType, string sender, string msg)
{
    if (MsgType~="Say" || MsgType~="TeamSay"){
        Level.Game.Broadcast(self,GenerateRGBTextCode(chatR,chatG,chatB)$"[Discord] "$sender$": "$msg);
    } else if (MsgType~="Heartbeat"){
        discordLink.SendHeartbeatResponse(sender,msg);
    }
}

function SendMsgToDiscord(coerce string MsgType, string sender, string msg, int teamIdx)
{
    discordLink.SendMsgToDiscord(MsgType,sender,msg,teamIdx);
}

defaultproperties
{
    bAddToServerPackages=True
    FriendlyName="Discord Bridge"
    Description="Bridges your in-game chat to a Discord server!||More information at: https://github.com/SarahRoseLives/UT2004DiscordBridge"
    discord_bridge_addr="127.0.0.1"
    bBridgeSay=True
    bBridgeTeamSay=False
    bBridgeKills=False
    bBridgeFlagCaps=False
    discord_bridge_port=49321
    chatR=224
    chatG=1
    chatB=224
}
