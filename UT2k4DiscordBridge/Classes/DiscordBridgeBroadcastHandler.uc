class DiscordBridgeBroadcastHandler extends BroadcastHandler;

var DiscordBridge mut;

function Init(DiscordBridge mutator)
{
    mut = mutator;
}

function int GetTeamIndexFromPRI(PlayerReplicationInfo pri)
{
    local int teamId;

    teamId=-1;
    if (pri.Team!=None){
        teamId=pri.Team.TeamIndex;
    }

    return teamId;
}

function BroadcastText( PlayerReplicationInfo SenderPRI, PlayerController Receiver, coerce string Msg, optional name Type )
{
    Super.BroadcastText(SenderPRI,Receiver,Msg,Type);

    //log ("Catching BroadcastText: SenderPRI "$SenderPRI$"   msg: "$Msg$"  Type: "$Type);
    if ((mut.bBridgeSay && Type=='Say') || (mut.bBridgeTeamSay && Type=='TeamSay')){
        mut.SendMsgToDiscord(Type, SenderPRI.PlayerName,msg,GetTeamIndexFromPRI(SenderPRI));
    }
}


//Can catch game events like player joins, flags being taken and dropped, kills
function BroadcastLocalized( Actor Sender, PlayerController Receiver, class<LocalMessage> Message, optional int Switch, optional PlayerReplicationInfo RelatedPRI_1, optional PlayerReplicationInfo RelatedPRI_2, optional Object OptionalObject )
{
    //GameMessage extends LocalMessage, that could be filtered on
    //CriticalEventPlus handles things like CTF events, first blood, killing spree, countdowns...
    Super.BroadcastLocalized(Sender,Receiver,Message,Switch,RelatedPRI_1,RelatedPRI_2,OptionalObject);

    if (mut.bBridgeKills && ClassIsChildOf(Message,class'xDeathMessage')){
        mut.SendMsgToDiscord("Kill","Game",Message.Static.GetString(Switch,RelatedPRI_1,RelatedPRI_2,OptionalObject),GetTeamIndexFromPRI(RelatedPRI_1));
    } else if (ClassIsChildOf(Message,class'CTFMessage')) {
        if (mut.bBridgeFlagCaps && Switch==0) { //Switch 0 is flag captures (see CTFMessage class)
            mut.SendMsgToDiscord("FlagCap","Game",Message.Static.GetString(Switch,RelatedPRI_1,RelatedPRI_2,OptionalObject),GetTeamIndexFromPRI(RelatedPRI_1));
        }
    } else if (ClassIsChildOf(Message,class'ONSOnslaughtMessage')) {
        if (mut.bBridgeRoundEnd && (Switch==0 || Switch==1)) { //Red Team / Blue Team won the round
            mut.SendMsgToDiscord("RoundEnd","Game",Message.Static.GetString(Switch,RelatedPRI_1,RelatedPRI_2,OptionalObject),Switch);
        }
    } else if (ClassIsChildOf(Message,class'xBombMessage')) {
        if (mut.bBridgeBRScores && Switch==0) {
            mut.SendMsgToDiscord("BRScore","Game",Message.Static.GetString(Switch,RelatedPRI_1,RelatedPRI_2,OptionalObject),GetTeamIndexFromPRI(RelatedPRI_1));
        }
    //} else {
    //    mut.SendMsgToDiscord("LocalizedMessage",string(Message),Message.Static.GetString(Switch,RelatedPRI_1,RelatedPRI_2,OptionalObject),-1);
    }
    //log("Catching BroadcastLocalized:  Sender "$Sender$"   Receiver: "$Receiver$"   Message: "$Message.Static.GetString(Switch,RelatedPRI_1,RelatedPRI_2,OptionalObject));
}