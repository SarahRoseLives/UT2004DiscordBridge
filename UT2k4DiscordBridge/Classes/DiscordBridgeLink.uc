class DiscordBridgeLink extends TcpLink transient;

var string discord_bridge_addr;
var int discord_bridge_port;
var DiscordBridge bridgeMut;

var int ListenPort;
var IpAddr addr;
var int reconnectTimer;
var bool enabled;

const ReconDefault = 5;

function Init(DiscordBridge mut, string addr, int port)
{
    bridgeMut = mut;
    discord_bridge_addr = addr; 
    discord_bridge_port = port;
    enabled = True;

    Resolve(discord_bridge_addr);

    reconnectTimer = ReconDefault;
    SetTimer(1,True);

}

simulated function Timer() {
    
    if (!IsConnected()) {
        reconnectTimer-=1;
        if (reconnectTimer <= 0){
            if (enabled){
                Resolve(discord_bridge_addr);
            }
        }
    }
}

simulated function handleMessage(string msg) {

    local string msgType,sender,sentMsg;
    local Json jmsg;

    jmsg = class'Json'.static.parse(Level, msg);
    msgType=jmsg.get("type");
    sender=jmsg.get("sender");
    sentMsg=jmsg.get("msg");

    if (msgType=="") return;

    bridgeMut.ReceiveMsgFromDiscord(msgType,sender,sentMsg);

}

function SendHeartbeatResponse(string sender, string msg)
{
    local string j, returnMsg;
    local class<Json> js;
    local bool validSender,validMsg;

    if (sender~="Discord") validSender = true;
    if (msg~="PING") validMsg = true;

    if (validSender && validMsg){
        returnMsg="PONG";
    } else {
        returnMsg="Invalid Heartbeat -";
        if (!validSender){
            returnMsg=returnMsg$" Sender: '"$sender$"'";
        }
        if (!validMsg){
            returnMsg=returnMsg$" Msg: '"$msg$"'";
        }
    }

    returnMsg = TruncateMsg(returnMsg);

    js = class'Json';

    j = js.static.Start("Heartbeat");
    js.static.Add(j,"sender","Mutator");
    js.static.Add(j,"msg",returnMsg);
    js.static.End(j);

    //log("Sending JSON message to Discord bridge: "$j);

    SendRawString(j);
}

function SendMsgToDiscord(string MsgType, string sender, string msg, int teamIdx)
{
    local string j;
    local class<Json> js;
    js = class'Json';

    msg = TruncateMsg(msg);

    j = js.static.Start(MsgType);
    js.static.Add(j,"sender",sender);
    js.static.Add(j,"teamIndex",teamIdx);
    js.static.Add(j,"msg",msg);
    js.static.End(j);

    //log("Sending JSON message to Discord bridge: "$j);
    SendRawString(j);
}

function String TruncateMsg(string msg)
{
    return Mid(msg,0,400);
}

function SendRawString(string msg)
{
    msg=msg$chr(4); //"End of Transmission" character as delimiter
    SendText(msg);
}

event Opened(){
    Level.Game.Broadcast(self,"Discord Bridge connection opened");
}

event Closed(){
    Level.Game.Broadcast(self,"Discord Bridge connection closed");
    ListenPort = 0;
    reconnectTimer = ReconDefault;
}

event ReceivedText( string Text )
{
    handleMessage(Text);
}

event Destroyed(){
    Close();
    Super.Destroyed();
}

function Resolved( IpAddr Addr )
{
    if (ListenPort == 0) {
        ListenPort=BindPort();
        if (ListenPort==0){
            Level.Game.Broadcast(self,"Failed to bind port for Discord Bridge");
            reconnectTimer = ReconDefault;
            return;
        }   
    }

    Addr.port=discord_bridge_port;
    if (False==Open(Addr)){
        Level.Game.Broadcast(self,"Could not connect to Discord Bridge");
        reconnectTimer = ReconDefault;
        return;

    }

}
function ResolveFailed()
{
    Level.Game.Broadcast(self,"Could not resolve Discord Bridge address");
    reconnectTimer = ReconDefault;
}

defaultproperties
{
    LinkMode=MODE_Text
    ReceiveMode=RMODE_Event
}