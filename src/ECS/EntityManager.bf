using System;
using System.Collections;
using System.Diagnostics;

namespace Dimtoo
{
	class EntityManager
	{
		readonly List<Entity> availableEntities = new .(MAX_ENTITIES) ~ delete _;
		Signature[MAX_ENTITIES] signatures;
		readonly HashSet<Entity> livingEntities = new .(MAX_ENTITIES) ~ delete _;

		[Inline]
		public this()
		{
			for (var i = MAX_ENTITIES - 1; i >= 0; i--)
				availableEntities.Add((uint16)i);
		}

		[Inline]
		public void ClearEntities()
		{
			availableEntities.Clear();
			for (var i = MAX_ENTITIES - 1; i >= 0; i--)
				availableEntities.Add((uint16)i);

			signatures = .();
			livingEntities.Clear();
		}

		[Inline]
		public Entity CreateEntity()
		{
			Runtime.Assert(livingEntities.Count < MAX_ENTITIES, "Too many entities");
			
			let newEnt = availableEntities.PopBack();
			livingEntities.Add(newEnt);
			return newEnt;
		}

		[Inline]
		public void DestroyEntity(Entity e)
		{
			Debug.Assert(e < MAX_ENTITIES, "Entity out of range");
			
			livingEntities.Remove(e);
			availableEntities.Add(e);
			signatures[e] = default;
		}

		public Signature this[Entity e]
		{
			[Inline]
			get
			{
				Debug.Assert(e < MAX_ENTITIES, "Entity out of range");

				return signatures[e];
			}

			[Inline]
			set
			{
				Debug.Assert(e < MAX_ENTITIES, "Entity out of range");

				signatures[e] = value;
			}
		}

		[Inline]
		public HashSet<Entity>.Enumerator EnumerateEntities()
		{
			return livingEntities.GetEnumerator();
		}
	}
}
