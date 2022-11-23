using System.Collections;
using System;
using Bon;
using Pile;

namespace Dimtoo
{
	class Translator
	{
		public static Dictionary<String, String> strings ~ if (_ != null) DeleteDictionaryAndKeysAndValues!(_);

		public static void SetLanguage(StringView file)
		{
			let old = strings;
			strings = new .(512);
			if (Bon.Deserialize(ref strings, file) case .Err)
			{
				Log.Error("Couldn't load language file");
				delete strings;
				strings = old;
			}
			else if (old != null) DeleteDictionaryAndKeysAndValues!(old);
		}

		public static StringView Get(String key)
		{
			if (strings.TryGet(key, ?, let val))
				return val;
			return key;
		}
	}
}