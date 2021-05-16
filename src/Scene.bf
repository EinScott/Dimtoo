using System;
using System.Collections;
using System.Diagnostics;
using Pile;

using internal Dimtoo;

namespace Dimtoo
{
	[AttributeUsage(.Class, .ReflectAttribute|.DisallowAllowMultiple)]
	struct UpdateAttribute : Attribute {}
	[AttributeUsage(.Class, .ReflectAttribute|.DisallowAllowMultiple)]
	struct RenderAttribute : Attribute {}
	[AttributeUsage(.Class, .ReflectAttribute|.DisallowAllowMultiple)]
	struct PriorityAttribute : Attribute, this(int updatePriority);
	/*[AttributeUsage(.Class)]
	struct RequireAttribute<T> : Attribute where T : ComponentBase
	{
		public const Type Required = typeof(T);
	}*/

	class Scene
	{
		public abstract class System
		{
			// For things acting on multiple components/entities, like collision, which is not really owned by a system
			// these should get callbacks for all the common actions
			// but also, these are characteristically not really accessed by the outside
		}

		BumpAllocator alloc = new .() ~ delete _;

		uint32 next = 1;
		Dictionary<Type, List<Component>> componentsByType = new .();
		internal Dictionary<uint32, Component> componentsByEntity = new .() ~ delete _; // ComponentBase has linked list

		public ~this()
		{
			for (let list in componentsByType.Values)
			{
				for (var value in list)
					delete:alloc value;
				delete list;
			}	

			delete componentsByType;
		}

		// get entities by tag, get components by attribute, get components by type, get components by entity
		// components are allocated and deleted only by this thing!
		// do get()s lookups respect inheritance? because they probably should

		// enable disable on entity and component layer

		[Inline]
		bool Valid(Entity e) => e.ID != default && e.Scene == this && e.ID < next;
		[Inline]
		bool InUse(Entity e) => Valid(e) && componentsByEntity.ContainsKey(e);

		public Entity CreateEntity()
		{
			let ent = Entity(next++, this);
			OnCreateEntity(ent);
			return ent;
		}
		public Entity CreateEntityWith<T>() where T : Component, new
		{
			let ent = Entity(next++, this);
			OnCreateEntity(ent);
			CreateComponent<T>(ent);

			return ent;
		}
		[Inline]
		protected virtual void OnCreateEntity(Entity e) {}

		public void DestroyEntity(Entity e)
		{
			Debug.Assert(InUse(e));

			if (componentsByEntity.TryGetValue(e, var itComp))
			{
				// Remove whole entry
				componentsByEntity.Remove(e);

				// Destroy all components
				while (itComp.nextOnEntity != null)
				{
					let comp = itComp;
					itComp = itComp.nextOnEntity;

					DestroyComponent(comp, false);
				}
			}
		}

		protected internal T CreateComponent<T>(Entity e) where T : Component, new
		{
			Debug.Assert(Valid(e));
			let component = new:alloc T();
			component.Entity = e;

			const Type type = typeof(T);
			if (!componentsByType.ContainsKey(type))
				componentsByType.Add(type, new .());
			componentsByType[type].Add(component);

			if (!componentsByEntity.ContainsKey(e))
				componentsByEntity.Add(e, component);
			else
			{
				// Append to linked list
				var itComp = componentsByEntity[e];
				while (itComp.nextOnEntity != null)
					itComp = itComp.nextOnEntity;

				itComp.nextOnEntity = component;
			}

			OnCreateComponent(component, e);

			component.[Friend]Attach();
			return component;
		}
		[Inline]
		protected virtual void OnCreateComponent(Component component, Entity e) {}

		protected internal void DestroyComponent(Component component, bool maintainEntityList = true)
		{
			Debug.Assert(InUse(component.Entity));

			OnDestroyComponent(component);

			componentsByType[component.GetType()].Remove(component);

			if (maintainEntityList)
			{
				Debug.Assert(componentsByEntity.TryGetValue(component.Entity, var itComp));

				if (itComp.nextOnEntity == null)
					componentsByEntity.Remove(component.Entity);
				else
				{
					bool removed = false;
					while (itComp.nextOnEntity != null)
					{
						if (itComp.nextOnEntity == component)
						{
							itComp.nextOnEntity = itComp.nextOnEntity.nextOnEntity; // This might be null and that's fine

							removed = true;
							break;
						}

						itComp = itComp.nextOnEntity;
					}
					Debug.Assert(removed);
				}
			}

			delete:alloc component;
		}
		[Inline]
		protected virtual void OnDestroyComponent(Component component) {}
	}
}
