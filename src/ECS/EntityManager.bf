using System;
using System.Collections;
using System.Diagnostics;

namespace Dimtoo
{
	class EntityManager
	{
		readonly List<Entity> availableEntities = new .(MAX_ENTITIES) ~ delete _;
		Signature[MAX_ENTITIES] signatures;
		uint16 livingEntityCount;

		[Inline]
		public this()
		{
			for (var i = MAX_ENTITIES - 1; i >= 0; i--)
				availableEntities.Add((uint16)i);
		}

		[Inline]
		public Entity CreateEntity()
		{
			Runtime.Assert(livingEntityCount < MAX_ENTITIES, "Too many entities");
			
			livingEntityCount++;
			return availableEntities.PopBack();
		}

		[Inline]
		public void DestroyEntity(Entity e)
		{
			Debug.Assert(e < MAX_ENTITIES, "Entity out of range");
			
			livingEntityCount--;
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
	}
}
