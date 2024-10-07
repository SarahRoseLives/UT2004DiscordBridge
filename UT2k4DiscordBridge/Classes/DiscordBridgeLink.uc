class DiscordBridgeLink extends TcpLink transient;

var string discord_bridge_addr;
var int discord_bridge_port;
var DiscordBridge bridgeMut;

var int ListenPort;
var IpAddr addr;
var int ticker;
var int reconnectTimer;
var string pendingMsg;
var bool enabled;

const ReconDefault = 5;

function Init(DiscordBridge mut, string addr, int port)
{
    bridgeMut = mut;
    discord_bridge_addr = addr; 
    discord_bridge_port = port;
    enabled = True;
    
    //Initialize the pending message buffer
    pendingMsg = "";
    
    //Initialize the ticker
    ticker = 0;

    Resolve(discord_bridge_addr);

    reconnectTimer = ReconDefault;
    SetTimer(0.1,True);

}

simulated function Timer() {
    
    ticker++;
    if (IsConnected()) {
        if (enabled){
            ManualReceiveBinary();
        }
    }

    if (ticker%10 != 0) {
        return;
    }

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
    local byte jbyte[255];
    local int i;
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

    js = class'Json';

    j = js.static.Start("Heartbeat");
    js.static.Add(j,"sender","Mutator");
    js.static.Add(j,"msg",returnMsg);
    js.static.End(j);

    //log("Sending JSON message to Discord bridge: "$j);

    for (i=0;i<Len(j);i++){
        jbyte[i]=Asc(Mid(j,i,1));
    }
    
    SendBinary(Len(j)+1,jbyte);
}

function SendMsgToDiscord(string MsgType, string sender, string msg, int teamIdx)
{
    local string j;
    local class<Json> js;
    local byte jbyte[255];
    local int i;
    js = class'Json';

    j = js.static.Start(MsgType);
    js.static.Add(j,"sender",sender);
    js.static.Add(j,"teamIndex",teamIdx);
    js.static.Add(j,"msg",msg);
    js.static.End(j);

    //log("Sending JSON message to Discord bridge: "$j);

    for (i=0;i<Len(j);i++){
        jbyte[i]=Asc(Mid(j,i,1));
    }
    
    SendBinary(Len(j)+1,jbyte);
}


//I cannot believe I had to manually write my own version of ReceivedBinary
simulated function ManualReceiveBinary() {
    local byte B[255]; //I have to use a 255 length array even if I only want to read 1
    local int count,i;
    //PlayerMessage("Manually reading, have "$DataPending$" bytes pending");
    
    if (DataPending!=0) {
        count = ReadBinary(255,B);
        for (i = 0; i < count; i++) {
            if (B[i] == 0) {
                if (Len(pendingMsg)>0){
                    handleMessage(pendingMsg);
                }
                pendingMsg="";
            } else {
                pendingMsg = pendingMsg $ Chr(B[i]);
                //PlayerMessage("ReceivedBinary: " $ B[i]);
            }
        }
    }
    
}
event Opened(){
    Level.Game.Broadcast(self,"Discord Bridge connection opened");
}

event Closed(){
    Level.Game.Broadcast(self,"Discord Bridge connection closed");
    ListenPort = 0;
    reconnectTimer = ReconDefault;
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

    //Using manual binary reading, which is handled by ManualReceiveBinary()
    //This means that we can handle if multiple Discord Bridge messages come in
    //between reads.
    LinkMode=MODE_Binary;
    ReceiveMode = RMODE_Manual;

}
function ResolveFailed()
{
    Level.Game.Broadcast(self,"Could not resolve Discord Bridge address");
    reconnectTimer = ReconDefault;
}

defaultproperties
{
    LinkMode=MODE_Binary
    ReceiveMode=RMODE_Manual
}