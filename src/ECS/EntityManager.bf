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
				availableEntities.Add((Entity)i);
		}

		[Inline]
		public bool EntityLives(Entity e) => livingEntities.Contains(e);

		[Inline]
		public void ClearEntities()
		{
			availableEntities.Clear();
			for (var i = MAX_ENTITIES - 1; i >= 0; i--)
				availableEntities.Add((Entity)i);

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

		public Result<void> CreateSpecificEntity(Entity e)
		{
			Runtime.Assert(livingEntities.Count < MAX_ENTITIES, "Too many entities");
			if (livingEntities.Contains(e))
				return .Err;
			
			availableEntities.Remove(e);
			livingEntities.Add(e);
			return .Ok;
		}

		[Inline]
		public void DestroyEntity(Entity e)
		{
			Debug.Assert(e < MAX_ENTITIES, "Entity out of range");
			
			livingEntities.Remove(e);
			availableEntities.Add(e);
			signatures[(int)e] = default;
		}

		public Signature this[Entity e]
		{
			[Inline]
			get
			{
				Debug.Assert(e < MAX_ENTITIES, "Entity out of range");

				return signatures[(int)e];
			}

			[Inline]
			set
			{
				Debug.Assert(e < MAX_ENTITIES, "Entity out of range");

				signatures[(int)e] = value;
			}
		}

		[Inline]
		public HashSet<Entity>.Enumerator EnumerateEntities()
		{
			return livingEntities.GetEnumerator();
		}
	}
}
