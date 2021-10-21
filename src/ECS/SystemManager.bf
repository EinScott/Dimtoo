using System;
using System.Collections;
using System.Diagnostics;

namespace Dimtoo
{
	abstract class ComponentSystem
	{
		public readonly Span<Type> signatureTypes;
		public readonly HashSet<Entity> entities = new HashSet<uint16>() ~ delete _;
		public ComponentManager componentManager;
	}

	class SystemManager
	{
		readonly Dictionary<Type, (Signature signature, ComponentSystem system)> systems = new .() ~ {
			for (var p in _.Values)
				delete p.system;
			delete _;
		};

		[Inline]
		public T RegisterSystem<T>() where T : ComponentSystem
		{
			Debug.Assert(!systems.ContainsKey(typeof(T)), "System already registered");

			let sys = new T();
			systems.Add(typeof(T), (default, sys));
			return sys;
		}

		[Inline]
		public void SetSignature<T>(Signature signature)
		{
			Debug.Assert(systems.ContainsKey(typeof(T)), "System not registered");

			systems[typeof(T)].signature = signature;
		}

		[Inline]
		public void OnEntityDestroyed(Entity e)
		{
			for (let tup in systems.Values)
				tup.system.entities.Remove(e);
		}

		[Inline]
		public void OnEntitySignatureChanged(Entity e, Signature sig)
		{
			for (let tup in systems)
			{
				// Add and remove from systems according to signature mask
				if ((tup.value.signature & sig) == tup.value.signature)
					tup.value.system.entities.Add(e);
				else tup.value.system.entities.Remove(e);
			}
		}
	}
}
