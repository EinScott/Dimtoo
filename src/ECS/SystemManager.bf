using System;
using System.Collections;
using System.Diagnostics;

namespace Dimtoo
{
	abstract class ComponentSystem
	{
		public readonly Span<Type> signatureTypes;
		public readonly HashSet<Entity> entitySet = new .() ~ delete _;
		public readonly List<Entity> entities = new .() ~ delete _;
		public Scene scene;

	}

	class SystemManager
	{
		readonly Dictionary<Type, (Signature signature, ComponentSystem system)> systems = new .() ~ {
			for (var p in _.Values)
				delete p.system;
			delete _;
		};

		[Inline]
		public void ClearSystemEntities()
		{
			for (let tup in systems.Values)
			{
				tup.system.entities.Clear();
				tup.system.entitySet.Clear();
			}
		}

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
			{
				tup.system.entities.Remove(e);
				tup.system.entitySet.Remove(e);
			}
		}

		[Inline]
		public void OnEntitySignatureChanged(Entity e, Signature sig)
		{
			for (let tup in systems.Values)
			{
				// Add and remove from systems according to signature mask
				if ((tup.signature & sig) == tup.signature)
				{
					if (!tup.system.entities.Contains(e))
					{
						// Maintain list sort, higher entity ids later
						int insertIdx = tup.system.entities.Count;
						for (let ent in tup.system.entities)
						{
							if ((uint16)ent > (uint16)e)
							{
								insertIdx = @ent.Index;
								break;
							}
						}
						tup.system.entities.Insert(insertIdx, e);
						tup.system.entitySet.Add(e);
					}
				}
				else
				{
					if (tup.system.entitySet.Remove(e))
						tup.system.entities.Remove(e);
				}
			}
		}
	}
}
