package scripts.jobQueue.script
{
	public class Utils
	{
		public function Utils()
		{
		}

		public static function trim(str:String):String
		{
		    for(var i:int = 0; str.charCodeAt(i) < 33; i++);
		    for(var j:int = str.length-1; str.charCodeAt(j) < 33; j--);
		    return str.substring(i, j+1);
		}
		public static function searchAndReplace(holder:String, searchfor:String, replacement:String) : String {
			var temparray:Array = holder.split(searchfor);
			var holder:String = temparray.join(replacement);
			return (holder);
		}
		
		public static function isNumeric(num:String):Boolean
		{
		    return !isNaN(parseInt(num));
		}		
		
		public static function rand(min:int, max:int) : int {
			return min + Math.random() * (max - min);
		}
		
		private static function format2(num:int) : String {
			if (num < 10) return "0" + num;
			return "" + num;
		}
		
		public static function getStringBetween(text:String, start:String, end:String) : String {
			var startInd:int = text.indexOf(start);
			if (startInd == -1) return null;
			startInd += start.length;
			var endInd:int = text.indexOf(end, startInd);
			if (endInd == -1) return null;
			var between:String = text.substring(startInd, endInd);
			return between;
		}
		
		public static function formatTime(num:int) : String {
			var hours:int = int(num / 3600);
			var minutes:int = int(num / 60) % 60;
			var seconds:int = num % 60;
			if (hours > 0) return hours + "h:" + format2(minutes) + "m:" + format2(seconds);
			return format2(minutes) + "m:" + format2(seconds);			
		}
		
		public static function randOrder(size:int) : Array {
			var arr:Array = new Array(size);
			var i:int;
			for (i = 0; i < size; i++) arr[i] = i;
			for (i = size-1; i >= 1; i--) {
				var j:int = Math.floor(Math.random() * i);
				var temp:int = arr[j];
				arr[j] = arr[i];
				arr[i] = temp;
			}
			return arr;
		}
	}
}