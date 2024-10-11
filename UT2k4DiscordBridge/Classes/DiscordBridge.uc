class DiscordBridge extends Mutator config(DiscordBridge);

var config string discord_bridge_addr;
var config int discord_bridge_port;
var config bool bBridgeSay;
var config bool bBridgeTeamSay;
var config bool bBridgeKills;
var config bool bBridgeFlagCaps;
var config bool bBridgeMatchEnd;
var config bool bBridgeBRScores;
var config bool bBridgeRoundEnd;
var config int  chatR;
var config int  chatG;
var config int  chatB;

var DiscordBridgeLink discordLink;
var DiscordBridgeBroadcastHandler chatHandler;

simulated function PreBeginPlay()
{
    local DiscordBridgeEventTrigger dbet;

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

    dbet = Spawn(class'DiscordBridgeEventTrigger');
    dbet.Init(self,'EndGame',0.1); //Gets notifications for the end of the game

    dbet = Spawn(class'DiscordBridgeEventTrigger');
    dbet.Init(self,'EndRound'); //Gets notifications for the end of an Assault round
}

function ExternalTrigger(name triggerTag)
{
    log("ExternalTrigger on DiscordBridge from "$triggerTag);

    if (triggerTag=='EndGame' && bBridgeMatchEnd){
        HandleEndGame();
    } else if (triggerTag=='EndRound' && bBridgeRoundEnd){
        HandleEndRound();
    }
}

function HandleEndRound()
{
    local ASGameInfo assGame;
    local GameObjective curObj;
    local int winTeamIdx;
    local string endMsg;

    assGame = ASGameInfo(Level.Game);
    if (assGame!=None){
        curObj = assGame.GetCurrentObjective();
        if (curObj.bDisabled){
            //attacking team won?
            winTeamIdx=assGame.CurrentAttackingTeam;
        } else {
            //Defending team won?
            if (assGame.CurrentAttackingTeam==0){
                winTeamIdx=1;
            } else {
                winTeamIdx=0;
            }
        }

        endMsg=ASGameReplicationInfo(assGame.GameReplicationInfo).GetRoundWinnerString();

        SendMsgToDiscord("RoundEnd","Game",endMsg,winTeamIdx);
    }
}

function HandleEndGame()
{
    local int TeamIdx;
    local string winner;
    local PlayerReplicationInfo pri;
    local TeamInfo team;

    if (Level.Game.GameReplicationInfo.Winner!=None){
        TeamIdx=-1;
        team = TeamInfo(Level.Game.GameReplicationInfo.Winner);
        pri = PlayerReplicationInfo(Level.Game.GameReplicationInfo.Winner);

        if (team!=None){
            TeamIdx=team.TeamIndex;
            winner = team.GetHumanReadableName();
        } else if (pri!=None){
            
            if (pri.Team!=None){
                TeamIdx=pri.Team.TeamIndex;
            }
            winner=pri.PlayerName;
        }
        SendMsgToDiscord("MatchEnd", winner, winner$" has won the match", TeamIdx);
    }
}

//This really makes sure the old discordLink is gone, since it seems like it used to kind of persist (despite being transient)
//which prevented the client from sending messages to the right one.  This was an issue I noticed with my Crowd Control mutator
function ServerTraveling(string URL, bool bItems)
{
    if (discordLink!=None){
        SendMsgToDiscord("ServerTravel","Game",URL,-1);

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
    PlayInfo.AddSetting("Discord Bridge", "bBridgeKills", "Notify Discord of Kills", 0, 1, "Check");
    PlayInfo.AddSetting("Discord Bridge", "bBridgeFlagCaps", "Notify Discord of Flag Captures", 0, 1, "Check");
    PlayInfo.AddSetting("Discord Bridge", "bBridgeMatchEnd", "Notify Discord of match end results", 0, 1, "Check");
    PlayInfo.AddSetting("Discord Bridge", "bBridgeBRScores", "Notify Discord of Bombing Run scores", 0, 1, "Check");
    PlayInfo.AddSetting("Discord Bridge", "bBridgeRoundEnd", "Notify Discord of round end results", 0, 1, "Check");
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
    //log("Received message from Discord: MsgType: "$MsgType);
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
    bBridgeMatchEnd=False
    bBridgeBRScores=False
    bBridgeRoundEnd=False
    discord_bridge_port=49321
    chatR=224
    chatG=1
    chatB=224
}
