using System;
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

		// enumerable stuff...
		// serializeable stuff
		// -> will also require some more methods in IVarStorageArrayBase
	}

	interface IVarStorageArrayBase
	{
		void ClearData();
	}

	class VarStorageArray<T> : IVarStorageArrayBase where T : struct
	{
		readonly List<T> storage = new .(256) ~ delete _;

		public void ClearData()
		{
			storage.Clear();
		}

		public void AddData(ref VarDataRef<T> reference, Span<T> data)
		{
			if (data.Length == 0)
				return;
			
			let newStart = storage.Count;
			
			if (reference.len != 0)
			{
				// Bogus "just add it AGAIN" realloc management
				// We'll clear it a lot, so it *should* be somewhat ok

				let oldSpan = storage.GetRange(reference.start, reference.len);
				storage.AddRange(oldSpan);
			}

			storage.AddRange(data);

			reference.start = newStart;
			reference.len += data.Length;
		}

		public Span<T> GetData(VarDataRef<T> reference)
		{
			return storage.GetRange(reference.start, reference.len);
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

		public Span<T> GetData<T>(VarDataRef<T> reference) where T : struct
		{
			return GetStorageArray<T>().GetData(reference);
		}

		[Inline]
		VarStorageArray<T> GetStorageArray<T>() where T : struct
		{
			Debug.Assert(storageArrays.ContainsKey(typeof(T)), "Storage type not registered");

			return (VarStorageArray<T>)storageArrays[typeof(T)];
		}
	}
}