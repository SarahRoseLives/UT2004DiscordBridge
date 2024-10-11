class DiscordBridgeEventTrigger extends Triggers;

var DiscordBridge discordMut;
var float triggerDelay;

function Init(DiscordBridge mut, name newTag, optional float delay)
{
    discordMut=mut;
    Tag=newTag;
    triggerDelay=delay;
}

function Trigger( actor Other, pawn EventInstigator )
{
    if (triggerDelay==0){
        discordMut.ExternalTrigger(Tag);
    } else {
        SetTimer(triggerDelay,False);
    }
}

function Timer() {
    discordMut.ExternalTrigger(Tag);
}


defaultproperties
{
    bCollideActors=False
}
