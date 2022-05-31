/*using System;
using Pile;
using System.Collections;
using System.Diagnostics;
using Bon;

// This is good for things like path data... a cleaner way to store, and centrally clearable
// unlike systems... but local system storage makes more sense right now when that is the only
// thing this storage was made for...
// -> we could use it for things like collision events... but their buffer is large enough
// and events are never shared right now and cleared every frame... so i just see the overhead
// and capacity is probably fine anyway... maybe later

namespace Dimtoo
{
	[BonTarget]
	struct VarDataRef<T> where T : struct
	{
		public int start;
		public int len;

		// enumerable stuff...
		// serializeable stuff
	}

	interface IVarStorageArrayBase
	{
		void ClearData();
	}

	class VarStorageArray<T> : IVarStorageArrayBase where T : struct
	{
		List<T> data = new .(256) ~ delete _;

		// There will be some "mem management" needed here...
		// -> add and remove will create holes
		// so have some... firstHole as a start spot for hole fit searching
		// also when removing, traverse back all default things aswell!

		// .. does that perf hit make this... feasable?
		// sure... for paths and stuff like that maybe, but for events?
		// but maybe we can use this for some bookkeeping instead of WorldData?
		// -> question there is just persistance, so it may not be quite right... nah..
		// => THIS IS FOR VAR-SIZE RUNTIME DATA (possibly also events...)

		public void ClearData()
		{

		}

		public void AddData() {}
		//public void RemoveData() {}
		public void GetData() {}
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

		}

		public void AddData<T>(ref VarDataRef<T> reference, params Span<T> data) where T : struct
		{

		}

		/*public void RemoveData<T>(ref VarDataRef<T> reference, int index, int length = 1) where T : struct
		{

		}*/

		public Span<T> GetData<T>(VarDataRef<T> reference) where T : struct
		{
			return default;
		}

		[Inline]
		VarStorageArray<T> GetStorageArray<T>() where T : struct
		{
			Debug.Assert(storageArrays.ContainsKey(typeof(T)), "Storage type not registered");

			return (VarStorageArray<T>)storageArrays[typeof(T)];
		}
	}
}*/