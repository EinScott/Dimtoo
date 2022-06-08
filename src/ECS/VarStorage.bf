// Doesn't seem to actually be more practical than just large enough buffers... memory isn't that sparse

/*using System;
using Pile;
using System.Collections;
using System.Diagnostics;
using Bon;

using internal Dimtoo;

namespace Dimtoo
{
	// => THIS IS FOR VAR-SIZE TEMPORARY RUNTIME DATA (like events!) *that get totally wiped frequently*

	[BonTarget]
	struct VarDataRef<T> where T : struct
	{
		[BonInclude]
		internal int start;
		[BonInclude]
		internal int len;
	}

	interface IVarStorageArrayBase
	{
		void ClearData();
		Span<uint8> GetSerializeData(int start, int len);
		Span<uint8> ReserveData(ref int start, ref int len, int reserve);
	}

	class VarStorageArray<T> : IVarStorageArrayBase where T : struct
	{
		readonly List<T> storage = new .(256) ~ delete _;

		public void ClearData()
		{
			storage.Clear();
		}

		void PrepareAdd(ref int start, ref int len, int addLen)
		{
			let newStart = storage.Count;

			if (len != 0)
			{
				// Bogus "just add it AGAIN" realloc management
				// We'll clear it a lot, so it *should* be somewhat ok

				let oldSpan = storage.GetRange(start, len);
				storage.AddRange(oldSpan);
			}

			start = newStart;
			len += addLen;
		}

		public void AddData(ref VarDataRef<T> reference, Span<T> data)
		{
			if (data.Length == 0)
				return;
			
			PrepareAdd(ref reference.start, ref reference.len, data.Length);

			storage.AddRange(data);
		}

		public Span<uint8> ReserveData(ref int start, ref int len, int reserve)
		{
			if (reserve == 0)
				return .();

			PrepareAdd(ref start, ref len, reserve);

			let ptr = storage.GrowUnitialized(reserve);

			return .((uint8*)ptr, reserve * strideof(T));
		}

		public Span<T> GetData(VarDataRef<T> reference)
		{
			if (reference.len == 0
				|| reference.start + reference.len > storage.Count)
				return .();

			return storage.GetRange(reference.start, reference.len);
		}

		public Span<uint8> GetSerializeData(int start, int len)
		{
			return storage.GetRange(start, len).ToRawData();
		}
	}

	class VarStorageManager
	{
		readonly Dictionary<Type, IVarStorageArrayBase> storageArrays = new .() ~ DeleteDictionaryAndValues!(_);

		[Inline]
		public void ClearData()
		{
			for (let storage in storageArrays.Values)
				storage.ClearData();
		}

		public void RegisterStorage<T>() where T : struct
		{
			Debug.Assert(!storageArrays.ContainsKey(typeof(T)), "Storage type already registered");

			storageArrays.Add(typeof(T), new VarStorageArray<T>());
		}

		public void AddData<T>(ref VarDataRef<T> reference, params Span<T> data) where T : struct
		{
			GetStorageArray<T>().AddData(ref reference, data);
		}

		public Span<uint8> ReserveData(Type t, ref int start, ref int len, int reserve)
		{
			Debug.Assert(storageArrays.ContainsKey(t), "Storage type not registered");

			return storageArrays[t].ReserveData(ref start, ref len, reserve);
		}

		public Span<T> GetData<T>(VarDataRef<T> reference) where T : struct
		{
			return GetStorageArray<T>().GetData(reference);
		}

		[Inline]
		public Span<uint8> GetSerializeData(Type t, int start, int len)
		{
			if (storageArrays.TryGetValue(t, let arr))
				return arr.GetSerializeData(start, len);
			return .();
		}

		[Inline]
		VarStorageArray<T> GetStorageArray<T>() where T : struct
		{
			Debug.Assert(storageArrays.ContainsKey(typeof(T)), "Storage type not registered");

			return (VarStorageArray<T>)storageArrays[typeof(T)];
		}
	}
}*/