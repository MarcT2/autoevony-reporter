package scripts.jobQueue.script
{
	import com.umge.sovt.client.action.ActionFactory;
	import com.umge.sovt.common.beans.MapCastleBean;
	import com.umge.sovt.common.constants.AllianceConstants;
	import com.umge.sovt.common.module.common.MapInfoResponse;
	import com.umge.sovt.common.module.field.OtherFieldInfoResponse;
	
	import flash.events.TimerEvent;
	import flash.utils.Timer;
	
	import mx.collections.ArrayCollection;
	
	public class Map
	{
		public static var fieldNames:Array = new Array("", "Forest", "Desert", "Hill", "Swamp",
			"GrassLand", "Lake", "", "", "", "Flat", "Castle", "NPC"
		);
				
		private static var timer:Timer = null;
		private static var map:Array = new Array();
		private static var detail:Array = new Array();
		private static var castles:Array = new Array;
		private static var pendingFieldId:Array = new Array();
		
		private static var WIDTH:int = 500;
		private static var HEIGHT:int = 500;
		private static var WSIZE:int = 10;
		
		public static function initMap(width:int, height:int) : void {
			WIDTH = width;
			HEIGHT = height;
		}
		
		public static function resetMap() : void {
			map = new Array();
			detail = new Array();
		}

		public static function fullResetMap() : void {
			map = new Array();
			detail = new Array();
			castles = new Array();
		}

		public static function resetArea(cx:int, cy:int, r:int) : void {
			for (var x:int = cx-r; x <= cx+r; x++) {
				for (var y:int = cy-r; y <= cy+r; y++) {
					if ((x-cx)*(x-cx) + (y-cy)*(y-cy) > r*r) continue;
					var fieldId:int = getFieldId(x, y);
					if (map[fieldId] != undefined) delete map[fieldId];
				} 
			}
		}

		public static function fieldIdToTypeString(fieldId:int) : String {
			var type:int = getType(fieldId);
			return (type == -1) ? "" : fieldNames[type];
		}

		public static function isMapReady(cx:int, cy:int, r:int) : Boolean {
			for (var x:int = cx-r; x <= cx+r; x++) {
				for (var y:int = cy-r; y <= cy+r; y++) {
					if ((x-cx)*(x-cx) + (y-cy)*(y-cy) > r*r) continue;
					if (getLevel(getFieldId(x, y)) == -1) return false;
				} 
			}
			return true;
		}
		
		public static function getLevel(fieldId:int) : int {
			if (map[fieldId] == undefined || map[fieldId] == null) {
				cacheMap(fieldId);
				return -1;
			}
			return map[fieldId] % 16;
		}
		
		public static function getType(fieldId:int) : int {
			if (map[fieldId] == undefined || map[fieldId] == null) {
				cacheMap(fieldId);
				return -1;
			}
			return map[fieldId] / 16;	
		}

		public static function updateInfo(fieldId:int) : void {
			if (map[fieldId] != undefined) {
				delete map[fieldId];
			}
			cacheMap(fieldId);
		}
			
		public static function updateDetailInfo(fieldId:int) : void {
			if (detail[fieldId] != undefined) {
				delete detail[fieldId];
			}
			cacheDetail(fieldId);
		}
		
		public static function getDetailInfo(fieldId:int) : MapCastleBean {
			if (detail[fieldId] == undefined) {
				cacheDetail(fieldId);
				return null;
			}
			return detail[fieldId];
		}

		public static function getX(fieldId:int) : int {		
			return fieldId % WIDTH;
		}
		
		public static function getY(fieldId:int) : int {		
			return fieldId / WIDTH;
		}
		
		public static function getFieldId(x:int, y:int) : int {
			if (x >= WIDTH) x -= WIDTH;
			if (x < 0) x += WIDTH;
			if (y >= HEIGHT) y -= HEIGHT;
			if (y < 0) y += HEIGHT;
			
			return y*WIDTH + x;
		}
		
		public static function fieldDistance(field1:int, field2:int) : Number {
			var x1:int = getX(field1), y1:int = getY(field1);
			var x2:int = getX(field2), y2:int = getY(field2);
			var dx:int = Math.abs(x1-x2); dx = Math.min(dx, WIDTH - dx);
			var dy:int = Math.abs(y1-y2); dy = Math.min(dy, HEIGHT - dy);
			return Math.sqrt(dx*dx + dy*dy);
		}

		private static var lastCacheMapTime:Date = null;
		private static function cacheMap(fieldId:int) : void {
			// make sure there is at most 1 cacheMap call every 3 seconds
			if (lastCacheMapTime != null && new Date().getTime() - lastCacheMapTime.getTime() < 2000) return;
			lastCacheMapTime = new Date();
			
			var x:int = getX(fieldId);
			var y:int = getY(fieldId);
			var startx:int = int(x/WSIZE) * WSIZE;
			var starty:int = int(y/WSIZE) * WSIZE;
			trace("Get map at " + startx + "," + starty + ", size: " + WSIZE);
			ActionFactory.getInstance().getCommonCommands().mapInfo(startx, starty, startx+WSIZE-1, starty+WSIZE-1, handleMapInfoResponse);
		}
		
		private static function handleMapInfoResponse(response:MapInfoResponse) : void {
			lastCacheMapTime = null;
			if (response.ok != 1) {
				trace("Unable to obtain map: " + response.msg);
				return;
			}

			if (response.mapStr == null) {
				trace("INVALID MAP RESPONSE RECEIVED -- NO MAP AVAILABLE!!!");
				return;
			}
			
			castles[getFieldId(response.x1, response.y1)] = response.castlesArray;
			var mapwidth:int = response.x2 - response.x1 + 1;
			for (var y:int = response.y1; y <= response.y2; y++) {
				for (var x:int = response.x1; x <= response.x2; x++) {
					var strPos:int = 2 * ((y-response.y1) * mapwidth + (x-response.x1));
					map[getFieldId(x,y)] = int("0x" + response.mapStr.substr(strPos, 2));
				}
			}
		}
		
		private static function cacheDetail(fieldId:int) : void {
			if (pendingFieldId.length > 100) return;
			pendingFieldId.push(fieldId);
			
			if (timer == null) {
				timer = new Timer(1500);
				timer.addEventListener(TimerEvent.TIMER, doFetchDetail);
				timer.start();
			}
		}

		private static function doFetchDetail(event:TimerEvent) : void {
			if (pendingFieldId.length == 0) return;
			var fieldId:int = pendingFieldId.pop();
			if (detail[fieldId] == undefined) {
				trace("Get detail info at " + getX(fieldId) + "," + getY(fieldId));
				ActionFactory.getInstance().getFieldCommand().getOtherFieldInfo(fieldId, handleGetFieldInfoResponse);
			}
		}

		private static function handleGetFieldInfoResponse(response:OtherFieldInfoResponse) : void {
			if (response.ok != 1) {
				trace("Unable to obtain field info: " + response.msg);
				return;
			}
			detail[response.bean.id] = response.bean;
		}
		public static function fieldIdToString(fieldId:int) : String {
			var x:int = getX(fieldId);
			var y:int = getY(fieldId);
			var level:int = getLevel(fieldId);
			var type:int = getType(fieldId);
			var typeStr:String = (type == -1) ? "" : fieldNames[type];
			var levelStr:String = (level == -1) ? "" : "" + level;
			return typeStr + " " + levelStr + "(" + x + "," + y + ")";
		}
		
		public static function fieldIdToCoordString(fieldId:int) : String {
			var x:int = getX(fieldId);
			var y:int = getY(fieldId);
			return "(" + x + "," + y + ")";
		}
		
		// search known castle by name or alliance
		public static function searchCastles(str:String) : Array {
			var result:Array = new Array();
			str = str.toLowerCase();
			for each (var arr:ArrayCollection in castles) {
				for each (var castle:MapCastleBean in arr) {
					if ((castle.allianceName != null && castle.allianceName.toLowerCase() == str) ||
						(castle.name != null && castle.name.toLowerCase() == str) ||
						(castle.userName != null && castle.userName.toLowerCase() == str)) 
					{
							result.push(castle);
					}
				}
			}
			return result;
		}
		
		// search known castle by name or alliance
		public static function searchEnemyCastles(str:String) : Array {
			var result:Array = new Array();
			str = str.toLowerCase();
			for each (var arr:ArrayCollection in castles) {
				for each (var castle:MapCastleBean in arr) {
					if (castle.relation == AllianceConstants.ENEMY_ALLIANCE) {
						result.push(castle);
					}
				}
			}
			return result;
		}
		
		public static function coordStringToFieldId(coords:String) : int {			
			var first:int;
			var second:int;
			coords = coords.replace(".", ",");
			var coordArray:Array = coords.split(",");
			
			if (coordArray.length == 2)
			{
				first = int(coordArray[0]);
				second = int(coordArray[1]);
				var teststring:String = "" + first + "," + second
				if (teststring == coords && WIDTH > 0 && first < WIDTH && second < HEIGHT)
				{ 
					return second * WIDTH + first;
				}
			}
			
			// -1 == and invalid coord was passed in.
			return -1;
		}
		
		public static function getFieldType(str:String) : int {
			for (var i:int = 0; i < fieldNames.length; i++) {
				if (fieldNames[i].length == 0) continue;
				if (fieldNames[i].toLowerCase() == str.toLowerCase()) return i;
			}
			return -1;
		}
	}
}