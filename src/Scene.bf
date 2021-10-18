using System;
using System.Collections;
using System.Diagnostics;
using Pile;

namespace Dimtoo
{
	typealias Entity = uint16;
	typealias ComponentType = uint8;

	struct Signature : uint64
	{
		[Inline]
		public void Add(uint8 bit) mut
		{
			this |= (1 << bit);
		}

		[Inline]
		public void Remove(uint8 bit) mut
		{
			this = this & ~(1 << bit);
		}
	}

	static
	{
		public const Entity MAX_ENTITIES = 4096;
		public const ComponentType MAX_COMPONENTS = 64;
	}

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

	interface ComponentArrayBase
	{
		void OnEntityDestroyed(Entity e);
	}

	class ComponentArray<T> : ComponentArrayBase where T : struct
	{
		T[MAX_ENTITIES] components;
		readonly Dictionary<Entity, int> entityToIndex = new .() ~ delete _;
		readonly List<Entity> indexToEntity = new .() ~ delete _;
		int size;

		public void InsertData(Entity e, T component)
		{
			Debug.Assert(!entityToIndex.ContainsKey(e), "Component added to the same entity more than once");

			let newIndex = size++;
			components[e] = component;

			// Add to lookups
			entityToIndex.Add(e, newIndex);
			if (indexToEntity.Count == newIndex)
				indexToEntity.Add(e);
			else indexToEntity[newIndex] = e;
		}

		public void RemoveData(Entity e)
		{
			Debug.Assert(entityToIndex.ContainsKey(e), "Component not present on this entity");

			let indexOfRemovedEntity = entityToIndex[e];
			let indexOfLastElement = --size;

			// Replace removed with last element
			components[indexOfRemovedEntity] = components[indexOfLastElement];

			// Update index of moved last element
			Entity entityOfLastElement = indexToEntity[indexOfLastElement];
			entityToIndex[entityOfLastElement] = indexOfRemovedEntity;
			indexToEntity[indexOfRemovedEntity] = entityOfLastElement;

			// Clean up lookup of removed
			entityToIndex.Remove(e);
			indexToEntity.PopBack();
		}

		[Inline]
		public T* GetData(Entity e)
		{
			Debug.Assert(entityToIndex.ContainsKey(e), "Component not present on this entity");

			return &components[entityToIndex[e]];
		}

		[Inline]
		public void OnEntityDestroyed(Entity e)
		{
			// If the entity had that component, remove it from us
			if (entityToIndex.ContainsKey(e))
				RemoveData(e);
		}
	}

	class ComponentManager
	{
		readonly Dictionary<Type, (ComponentType type, ComponentArrayBase array)> componentArrays = new .() ~ {
			for (let a in _)
				delete a.value.array;
			delete _;
		};
		ComponentType nextType;

		[Inline]
		public void RegisterComponent<T>() where T : struct
		{
			Debug.Assert(!componentArrays.ContainsKey(typeof(T)), "Component type already registered");

			componentArrays.Add(typeof(T), (nextType++, new ComponentArray<T>()));
		}

		[Inline]
		public ComponentType GetComponentType<T>() where T : struct
		{
			Debug.Assert(componentArrays.ContainsKey(typeof(T)), "Component type not registered");

			return componentArrays[typeof(T)].type;
		}

		[Inline]
		public ComponentType GetComponentType(Type t)
		{
			Debug.Assert(componentArrays.ContainsKey(t), "Component type not registered");

			return componentArrays[t].type;
		}

		[Inline]
		public void AddComponent<T>(Entity e, T component) where T : struct
		{
			GetComponentArray<T>().InsertData(e, component);
		}

		[Inline]
		public void RemoveComponent<T>(Entity e) where T : struct
		{
			GetComponentArray<T>().RemoveData(e);
		}

		[Inline]
		public T* GetComponent<T>(Entity e) where T : struct
		{
			return GetComponentArray<T>().GetData(e);
		}

		[Inline]
		public void OnEntityDestroyed(Entity e)
		{
			// Notify all componentArrays
			for (let tup in componentArrays.Values)
				tup.array.OnEntityDestroyed(e);
		}

		[Inline]
		ComponentArray<T> GetComponentArray<T>() where T : struct
		{
			Debug.Assert(componentArrays.ContainsKey(typeof(T)), "Component type not registered");

			return (ComponentArray<T>)componentArrays[typeof(T)].array;
		}
	}

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

	class Scene
	{
		protected readonly SystemManager sysMan = new .() ~ delete _;
		protected readonly ComponentManager compMan = new .() ~ delete _;
		protected readonly EntityManager entMan = new .() ~ delete _;

		[Inline]
		public Entity CreateEntity() => entMan.CreateEntity();

		public void DestroyEntity(Entity e)
		{
			entMan.DestroyEntity(e);
			compMan.OnEntityDestroyed(e);
			sysMan.OnEntityDestroyed(e);
		}

		[Inline]
		public void RegisterComponent<T>() where T : struct => compMan.RegisterComponent<T>();

		public void AddComponent<T>(Entity e, T component) where T : struct
		{
			compMan.AddComponent(e, component);

			var sig = entMan[e];
			sig.Add(compMan.GetComponentType<T>());
			entMan[e] = sig;

			sysMan.OnEntitySignatureChanged(e, sig);
		}

		public void RemoveComponent<T>(Entity e) where T : struct
		{
			compMan.RemoveComponent<T>(e);

			var sig = entMan[e];
			sig.Remove(compMan.GetComponentType<T>());
			entMan[e] = sig;

			sysMan.OnEntitySignatureChanged(e, sig);

		}

		[Inline]
		public T* GetComponent<T>(Entity e) where T : struct => compMan.GetComponent<T>(e);

		[Inline]
		public ComponentType GetComponentType<T>() where T : struct => compMan.GetComponentType<T>();

		[Inline]
		public T RegisterSystem<T>() where T : ComponentSystem
		{
			let sys = sysMan.RegisterSystem<T>();
			
			// Assemble signature from the system's requirements
			// Will error if the given types aren't already registered components
			Signature s = default;
			for (let t in sys.signatureTypes)
				s.Add(compMan.GetComponentType(t));
			sysMan.SetSignature<T>(s);

			sys.componentManager = compMan;
			return sys;
		}
	}

	struct Transform
	{
		public Vector2 position;
		public Vector2 scale;
		public float rotation;

		public this() { this = default; scale = .One; }
		public this(Vector2 position, Vector2 scale = .One, float rotation = 0)
		{
			this.position = position;
			this.scale = scale;
			this.rotation = rotation;
		}
	}
}
