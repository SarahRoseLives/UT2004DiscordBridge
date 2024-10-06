class DiscordBridgeBroadcastHandler extends BroadcastHandler;

var DiscordBridge mut;

function Init(DiscordBridge mutator)
{
    mut = mutator;
}

function BroadcastText( PlayerReplicationInfo SenderPRI, PlayerController Receiver, coerce string Msg, optional name Type )
{
    local int teamId;
    Super.BroadcastText(SenderPRI,Receiver,Msg,Type);

    //log ("Catching BroadcastText: SenderPRI "$SenderPRI$"   msg: "$Msg$"  Type: "$Type);
    if ((mut.bBridgeSay && Type=='Say') || (mut.bBridgeTeamSay && Type=='TeamSay')){
        teamId=-1;
        if (SenderPRI.Team!=None){
            teamId=SenderPRI.Team.TeamIndex;
        }
        mut.SendMsgToDiscord(Type, SenderPRI.PlayerName,msg,teamId);
    }
}


//Can catch game events like player joins, flags being taken and dropped, kills
function BroadcastLocalized( Actor Sender, PlayerController Receiver, class<LocalMessage> Message, optional int Switch, optional PlayerReplicationInfo RelatedPRI_1, optional PlayerReplicationInfo RelatedPRI_2, optional Object OptionalObject )
{
    local int teamId;

    //GameMessage extends LocalMessage, that could be filtered on
    //CriticalEventPlus handles things like CTF events, first blood, killing spree, countdowns...
    Super.BroadcastLocalized(Sender,Receiver,Message,Switch,RelatedPRI_1,RelatedPRI_2,OptionalObject);

    if (mut.bBridgeKills && ClassIsChildOf(Message,class'xDeathMessage')){
        teamId=-1;
        //In xDeathMessage, RelatedPRI_1 is the Killer
        if (RelatedPRI_1.Team!=None){
            teamId=RelatedPRI_1.Team.TeamIndex;
        }
        mut.SendMsgToDiscord("Kill","Game",Message.Static.GetString(Switch,RelatedPRI_1,RelatedPRI_2,OptionalObject),-1);
    }
    //log("Catching BroadcastLocalized:  Sender "$Sender$"   Receiver: "$Receiver$"   Message: "$Message.Static.GetString(Switch,RelatedPRI_1,RelatedPRI_2,OptionalObject));
}