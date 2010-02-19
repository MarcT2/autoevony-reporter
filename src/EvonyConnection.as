package {
	import com.adobe.crypto.SHA1;
	import com.umge.net.client.GameClientEvent;
	import com.umge.sovt.client.action.ActionFactory;
	import com.umge.sovt.client.response.ResponseDispatcher;
	import com.umge.sovt.common.Sender;
	import com.umge.sovt.common.constants.CommonConstants;
	import com.umge.sovt.common.server.events.LoginResponse;
	
	import flash.display.*;
	import flash.errors.EOFError;
	import flash.errors.IOError;
	import flash.events.Event;
	import flash.events.IOErrorEvent;
	import flash.events.ProgressEvent;
	import flash.events.SecurityErrorEvent;
	import flash.events.TimerEvent;
	import flash.net.Socket;
	import flash.text.*;
	import flash.utils.ByteArray;
	import flash.utils.Timer;
	
	import mx.controls.Alert;
	
	import scripts.jobQueue.script.ScriptLogEvent;
	import scripts.jobQueue.script.Utils;

	public class EvonyConnection extends Sprite implements Sender
	{

		private var m_socket:Socket;
		private var m_lock:Boolean = false;
		private var m_dataLength:int = 0;
		private var m_readed:int = 0;
		private static const MAX_PACKAGE_LEN:int = 1048576;
		private var m_mainBuffer:ByteArray;
		private var m_processedCount:int;
		private var m_amfObj:Object;
		private var m_username:String, m_password:String, m_server:String;
		public var m_reconnectTimer:Timer = new Timer(10000);
		public var m_authenticated:Boolean = false;
		private var m_connectAttempts:int = 0;

		public var paused:Boolean = false;

		public function EvonyConnection(username:String, password:String, server:String){

			m_socket = new Socket();

			this.m_username = username;
			this.m_password = password;
			this.m_server = server;
			var onExtensionResponseHandle:Function =
				function (param1:GameClientEvent) : void
				{
					ResponseDispatcher.getInstance().dispatch(param1.cmd, param1.data);
				};

			addEventListener(GameClientEvent.ON_EXTENSION_RESPONSE, onExtensionResponseHandle);

			ResponseDispatcher.getInstance().addEventListener(ResponseDispatcher.SERVER_LOGIN_RESPONSE, onLogin);
			ActionFactory.getInstance().setSender(this);

			// connect / disconnect
			m_socket.addEventListener(Event.CONNECT, connectionHandler);
			m_socket.addEventListener(Event.CLOSE, disconnectHandler);
			// data
			m_socket.addEventListener(ProgressEvent.SOCKET_DATA, dataHandler);
			// error
			m_socket.addEventListener(IOErrorEvent.IO_ERROR, ioErrorHandler);
			m_socket.addEventListener(SecurityErrorEvent.SECURITY_ERROR, ioErrorHandler);
			m_reconnectTimer.addEventListener("timer", reconnectHandler);
			connect();
		}

		public function connect():void
		{
			m_socket.connect(m_server, 443);
		}
		
		public function disconnect() : void
		{
			try
			{
				m_socket.close();	
			}
			catch (e:Error) {}
			
			m_readed = 0;
			m_dataLength = 0;
			m_mainBuffer = null;
			m_processedCount = 0;
			m_amfObj = null;
			m_authenticated = false;
		}

		public function sendMessage(param1:String, param2:Object):void
		{

			if(!m_authenticated) {
				return;
				//throw new Error("Connection error!");
			}
			_sendMessage(param1, param2);
		}

		private function connectionHandler(param1:Event) : void
		{
			// send version
			trace("sent version");
		    _sendMessage("gameClient.version",  "091103_11");

			// send login info
			trace("sent login info");
			var obj:Object = new Object();
			obj["user"] = m_username;
			obj["pwd"] = getHashedPassword();
			_sendMessage(CommonConstants.LOGIN_CMD, obj);
		}

		public function getHashedPassword() : String {
			return SHA1.hash(m_password);;
		}
		private function dataHandler(event:Event) : void
		{
			var needRead:int;
			var tempBuffer:ByteArray;
			var e:Event = event;
			if (m_lock)
			{
				// throw new Error("Socket.bytesAvailable=" + socket.bytesAvailable + "\tprocessedCount=" + processedCount + "\treaded=" + readed + " dataLength:" + dataLength);
				return;
			}// end if
			m_lock = true;
			while (m_socket.bytesAvailable > 0)
			{
				// label
				trace("GameClient.incomingDataHandler(): incoming data length:" + m_socket.bytesAvailable);
				if (m_dataLength == 0)
				{
					try
					{
						m_dataLength = m_socket.readInt();
					}
					catch (eof:EOFError)
					{
						// Jared - not sure what to do about this yet
						trace ("Hit EOF doing readInt");
						break;
					}

					m_readed = 0;
					if (m_dataLength > MAX_PACKAGE_LEN || m_dataLength < 0)
					{
						throw new Error("The package size is illegal. len=" + m_dataLength);
					}// end if
					m_mainBuffer = new ByteArray();
					m_processedCount = 0;
					trace("GameClient.incomingDataHandler(): New package.incomingLen:" + m_socket.bytesAvailable + " dataLength:" + m_dataLength);
				}// end if

				needRead = m_dataLength - m_readed;
				if (needRead > this.m_socket.bytesAvailable)
				{
					needRead = this.m_socket.bytesAvailable;
				}// end if
				if (needRead < 0)
				{
					throw new Error("The package available size is illegal .lenNeedRead=" + needRead + "\tremain=" + m_socket.bytesAvailable + "\tprocessedCount=" + m_processedCount + "\treaded=" + m_readed);
				}// end if
				try
				{
					this.m_readed = this.m_readed + needRead;
					tempBuffer = new ByteArray();
					m_socket.readBytes(tempBuffer, 0, needRead);
					m_mainBuffer.writeBytes(tempBuffer);
					m_processedCount++;
				}// end try
				catch (err:Error)
				{
					dispatchEvent(new GameClientEvent(GameClientEvent.ON_ERROR));
					return;
				}// end catch

				trace("GameClient.incomingDataHandler(): reading data. lenNeedRead=" + needRead + "\tremain=" + m_socket.bytesAvailable + "\tprocessedCount=" + m_processedCount + "\treaded=" + m_readed);
				if (m_readed == m_dataLength)
				{
					trace("GameClient.incomingDataHandler(): object length: " + m_readed);
					this.m_lock = false;
					m_mainBuffer.position = 0;
					try {
						m_amfObj = m_mainBuffer.readObject();
					}
					catch (err:RangeError)
					{
						dispatchEvent(new ScriptLogEvent("An error occurred while talking to the server. We're restarting the connection. Hang tight!"));
						disconnectHandler(null);
					}
					m_mainBuffer = null;
					m_dataLength = 0;
					m_processedCount = 0;
					m_readed = 0;
					if (!m_amfObj)
					{
						dispatchEvent(new GameClientEvent(GameClientEvent.ON_ERROR));
						return;
					}// end if

					dispatchEvent(new GameClientEvent(GameClientEvent.ON_EXTENSION_RESPONSE, m_amfObj));
				}// end if
			}// end while
			this.m_lock = false;
			return;
		}

		private function disconnectHandler(param1:Event) : void
		{
			m_authenticated = false;
			
			if (paused) {
				dispatchEvent(new ScriptLogEvent("Disconnected from server"));
			} else {
				dispatchEvent(new ScriptLogEvent("Disconnected from server, retry in " + Utils.formatTime(m_reconnectTimer.delay/1000)));
			}
			
			try
			{
				disconnect();				
			}
			catch(e:IOError) {}

			dispatchEvent(new GameClientEvent(ResponseDispatcher.SERVER_CONNECTION_LOST));
			m_reconnectTimer.start();
		}

		private function ioErrorHandler(e:Event) : void
		{
			m_authenticated = false;
			dispatchEvent(new GameClientEvent(GameClientEvent.ON_ERROR));
		}
	
		private function onLogin(response:LoginResponse) : void
		{
			trace("logged in!");
	
			if (response.player == null)
			{
				Alert.show("You have not logged in to this server ever before. So use the real game client to setup your name and other details," +
				"then use this client to connect.");
				return;
			}
			
			m_reconnectTimer.delay = Utils.rand(15000, 30000);
			m_authenticated = true;
			m_connectAttempts = 0;
		}
	
		private function reconnectHandler(event:TimerEvent) : void
		{
			var MAXQUICKATTEMPTS:int = 3;
			if (paused)
			{
				return;
			}

			if (m_authenticated)
			{
				m_reconnectTimer.stop();
				return;
			}
			
			dispatchEvent(new ScriptLogEvent("Attempt to reconnect..."));
			connect();
			m_connectAttempts++;
			if (m_connectAttempts > MAXQUICKATTEMPTS)
			{
				if (m_socket.connected)
				{
					try
					{
						m_socket.close();
					}
					catch (e:Error) {}
				}

				if (m_connectAttempts == MAXQUICKATTEMPTS+1) {
					m_reconnectTimer.delay = Utils.rand(8*60*1000, 10*60*1000); // 8-10 min
					dispatchEvent(new ScriptLogEvent("Too many failed reconnections, next retry in " + Utils.formatTime(m_reconnectTimer.delay/1000)));
				}
			}
		}
		
		private function _sendMessage(command:String, data:Object):void
		{
			if (m_socket.connected)
			{
				var obj:Object = new Object();
				obj.data = data;
				obj.cmd = command;
				var buffer:ByteArray = new ByteArray();
				buffer.writeObject(obj);
				m_socket.writeInt(buffer.length);
				m_socket.writeBytes(buffer);
				m_socket.flush();
			}
		}
	}
}