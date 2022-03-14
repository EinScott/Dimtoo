using System;
using System.IO;
using System.Collections;
using System.Diagnostics;
using Pile;
using Bon;
using Bon.Integrated;
using System.Reflection;

using internal Dimtoo;

namespace Dimtoo
{
	class ComponentSerializer
	{
		BonEnvironment env = new .() ~ delete _;
		Scene scene;

		static void BonError(StringView message)
		{
			Log.Debug(message);
		}

		static this()
		{
			Bon.onDeserializeError.Add(new => BonError); // TODO: temp
		}

		// This is a bit hacky, since this is basically all just call-internal
		// data, but this makes it very easy to interface with bon the way we do

		// SERIALIZE STATE
		Span<Entity> serializedEntities;

		// DESERIALIZE STATE
		List<Entity> deserializedEntities = new .() ~ delete _;
		List<(int indexRef, ValueView value)> deferResolveEntityRefs = new .() ~ delete _;

		public this(Scene scene)
		{
			this.scene = scene;

#if DEBUG
			env.serializeFlags |= .Verbose;
#endif

			env.allocHandlers.Add(typeof(String), new => MakeString);
			env.stringViewHandler = new => StringViewHandler;
			env.typeHandlers.Add(typeof(Entity), ((.)new => SerializeEntity, (.)new => DeserializeEntity));
			env.typeHandlers.Add(typeof(Asset<>), ((.)new => SerializeAsset, (.)new => DeserializeAsset));
		}

		void SerializeEntity(BonWriter writer, ValueView val, BonEnvironment env)
		{
			Entity entity = val.Get<Entity>();
			if (serializedEntities.Ptr != null && entity != .Invalid)
			{
				// If we don't keep the id's of entities, convert those to ref indices in the save data
				// entities.Ptr will only not be null, when we do not keep entity ids

				bool found = false;
				for (let i < serializedEntities.Length)
					if (serializedEntities[i] == entity)
					{
						found = true;

						// Instead reference that the value is the id of the 'x'th entity we're saving
						writer.Reference(i.ToString(.. scope .()));
						break;
					}

				if (!found)
				{
					Log.Warn("A serialized component contains a reference to an entity not included in the save. Since the save does not include exact entity ids, this field will not be serialized!");
					writer.Null();
				}
			}
			else entity.ToString(writer.outStr);
		}

		Result<void> DeserializeEntity(BonReader reader, ValueView val, BonEnvironment env)
		{
			if (reader.IsNull())
			{
				// Invalid
				val.Assign(0);
			}
			else
			{
				bool isRef = reader.IsReference();

				if (!isRef)
				{
					let entStr = Try!(reader.Integer());
					Entity ent = Try!(Deserialize.ParseInt<uint16>(reader, entStr, false));
					val.Assign(ent);
				}
				else
				{
					Try!(reader.Reference());

					let entStr = Try!(reader.Integer());
					uint16 ent = Try!(Deserialize.ParseInt<uint16>(reader, entStr, false));
					deferResolveEntityRefs.Add(((.)ent, val));
				}
			}

			return .Ok;
		}

		void SerializeAsset(BonWriter writer, ValueView val, BonEnvironment env)
		{
			if (val.type.GetField("name") case .Ok(let nameField))
			{
				// Just serialize the name as the whole asset.. other stuff is just internal runtime info!
				Serialize.Value(writer, ValueView(nameField.FieldType, ((uint8*)val.dataPtr) + nameField.MemberOffset), env);
			}
			else
			{
				Log.Warn("Couldn't serialize asset");
				writer.Null();
			}
		}

		Result<void> DeserializeAsset(BonReader reader, ValueView val, BonEnvironment env)
		{
			if (reader.IsNull())
			{
				// Invalid
				Try!(Deserialize.MakeDefault(reader, val, env));
			}
			else if (val.type.GetField("name") case .Ok(let nameField))
			{
				// TODO: would be nice to properly call constructor?

				// Fill in name field!
				Try!(Deserialize.Value(reader, ValueView(nameField.FieldType, ((uint8*)val.dataPtr) + nameField.MemberOffset), env));
			}
			else Deserialize.Error!("Couldn't deserialize asset", reader);

			return .Ok;
		}

		StringView StringViewHandler(StringView str)
		{
			return scene.managedStrings.Add(.. new String(str));
		}

		void MakeString(ValueView thing)
		{
			thing.Assign(scene.managedStrings.Add(.. new String()));
		}

		public void SerializeScene(String buffer, bool exactEntity = true)
		{
			let writer = scope BonWriter(buffer, env.serializeFlags.HasFlag(.Verbose));
			Serialize.Start(writer);

			using (writer.ArrayBlock())
			{
				Entity[] ent = null;
				if (!exactEntity)
				{
					// For this to work, we need a predictable order
					serializedEntities = scene.[Friend]entMan.[Friend]livingEntities.CopyTo(.. scope Entity[scene.[Friend]entMan.[Friend]livingEntities.Count]);

					for (let entity in ent)
					{
						SerializeEntity(writer, entity, buffer, exactEntity);
					}

					serializedEntities = default;
				}
				else
				{
					serializedEntities = default;

					for (let entity in scene.EnumerateEntities())
					{
						SerializeEntity(writer, entity, buffer, exactEntity);
					}
				}
			}

			Serialize.End(writer);
		}

		public void SerializeGroup(Entity[] entities, String buffer, bool exactEntity = true)
		{
			let writer = scope BonWriter(buffer);
			Serialize.Start(writer);

			serializedEntities = exactEntity ? .() : entities;

			using (writer.ArrayBlock())
			{
				for (let entity in entities)
				{
					if (!scene.EntityLives(entity))
						continue;

					SerializeEntity(writer, entity, buffer, exactEntity);
				}
			}

			Serialize.End(writer);
		}

		void SerializeEntity(BonWriter writer, Entity e, String buffer, bool exactEntity)
		{
			if (exactEntity)
			{
				var e;
				Serialize.Value(writer, ValueView(typeof(Entity), &e), env);
				writer.Pair();
			}

			using (writer.ArrayBlock())
			{
				for (let entry in scene.compMan.[Friend]componentArrays) // TODO: more general interface!
					if (entry.value.array.GetSerializeData(e, let data))
					{
						Serialize.Type(writer, entry.key);
						writer.Pair();
						Serialize.Value(writer, ValueView(entry.key, data.Ptr), env);
					}
			}

			writer.EntryEnd();
		}

		public Result<void> Deserialize(StringView buffer, List<Entity> createdEntities = null)
		{
			let reader = scope BonReader();
			Try!(reader.Setup(buffer));
			Try!(Deserialize.Start(reader));

			Try!(reader.ArrayBlock());

			deserializedEntities.Clear();
			deferResolveEntityRefs.Clear();

			while (reader.ArrayHasMore())
			{
				Try!(DeserializeEntity(reader));

				if (reader.ArrayHasMore())
					Try!(reader.EntryEnd());
			}

			Try!(reader.ArrayBlockEnd());
			/*let context =*/ Try!(Deserialize.End(reader));

			// Only added to when we have entity refs!
			if (deferResolveEntityRefs.Count > 0)
			{
				// This list should be filled with at least something, since clearly values were read
				// And new entities should have been created
				Debug.Assert(deserializedEntities.Count != 0);

				// Fill in all these values with the Entity values we get from the array
				for (var set in deferResolveEntityRefs)
					*((Entity*)set.value.dataPtr) = deserializedEntities[set.indexRef];
			}

			if (createdEntities != null)
				createdEntities.AddRange(deserializedEntities);

			return .Ok;
		}

		Result<void> DeserializeEntity(BonReader reader)
		{
			Entity e = 0;
			if (reader.inStr.Length > 0 && reader.inStr[0].IsDigit)
			{
				Try!(Deserialize.Value(reader, ValueView(typeof(Entity), &e), env));

				if (e >= MAX_ENTITIES)
					LogErrorReturn!("Entity out of range");

				if (scene.CreateSpecificEntitiy(e) case .Err)
					LogErrorReturn!("Requested entity already exists");

				Try!(reader.Pair());
			}
			else
			{
				// Just take any available entity
				e = scene.CreateEntity();
			}

			deserializedEntities.Add(e);

			Try!(reader.ArrayBlock());

			while (reader.ArrayHasMore())
			{
				// Get type from name
				let typeName = Try!(reader.Type());
				if (!env.TryGetPolyType(typeName, let componentType))
					LogErrorReturn!("Failed to find component type in bonEnv.polyTypes");

				let structMemory = scene.ReserveComponent(e, componentType);

				Try!(reader.Pair());
				Try!(Deserialize.Struct(reader, ValueView(componentType, structMemory.Ptr), env));

				if (reader.ArrayHasMore())
					Try!(reader.EntryEnd());
			}

			Try!(reader.ArrayBlockEnd());

			return .Ok;
		}
	}
}
