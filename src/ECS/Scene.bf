using System;
using System.Collections;
using System.Diagnostics;
using Pile;

namespace Dimtoo
{
	typealias Entity = uint16;
	typealias ComponentType = uint8;

	static
	{
		public const Entity MAX_ENTITIES = 4096;
		public const ComponentType MAX_COMPONENTS = 64;
	}

	class Scene
	{
		protected readonly SystemManager sysMan = new .() ~ delete _;
		protected readonly ComponentManager compMan = new .() ~ delete _;
		protected readonly EntityManager entMan = new .() ~ delete _;

		protected readonly ComponentSerializer serializer = new .(compMan) ~ delete _;

		public void Clear()
		{
			entMan.ClearEntities();
			sysMan.ClearSystemEntities();
			compMan.ClearData();
		}

		[Inline]
		public void SerializeScene(String buffer, bool includeDefault = false, bool exactEntity = true) => serializer.SerializeScene(this, buffer, exactEntity, includeDefault);

		[Inline]
		public bool DeserializeScene(StringView saveString) => serializer.DeserializeScene(this, saveString) case .Ok;

		[Inline]
		public Entity CreateEntity() => entMan.CreateEntity();

		[Inline]
		public Result<void> CreateSpecificEntitiy(Entity e) => entMan.CreateSpecificEntity(e);

		[Inline]
		public bool DeserializeEntity(StringView saveString) => serializer.DeserializeEntity(this, saveString) case .Ok;

		[Inline]
		public void SerializeEntity(Entity e, String buffer, bool includeDefault = false, bool exactEntity = false) => serializer.SerializeEntity(e, buffer, exactEntity, includeDefault);

		public void DestroyEntity(Entity e)
		{
			entMan.DestroyEntity(e);
			compMan.OnEntityDestroyed(e);
			sysMan.OnEntityDestroyed(e);
		}

		[Inline]
		public bool EntityLives(Entity e) => entMan.EntityLives(e);

		[Inline]
		public void RegisterComponent<T>() where T : struct => compMan.RegisterComponent<T>();

		public void AddComponent<T>(Entity e, T component) where T : struct
		{
			Debug.Assert(entMan.EntityLives(e));
			compMan.AddComponent(e, component);

			var sig = entMan[e];
			sig.Add(compMan.GetComponentType<T>());
			entMan[e] = sig;

			sysMan.OnEntitySignatureChanged(e, sig);
		}

		public Span<uint8> ReserveComponent(Entity e, Type componentType)
		{
			Debug.Assert(entMan.EntityLives(e));
			let span = compMan.ReserveComponent(e, componentType);

			var sig = entMan[e];
			sig.Add(compMan.GetComponentType(componentType));
			entMan[e] = sig;

			sysMan.OnEntitySignatureChanged(e, sig);

			return span;
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
}
