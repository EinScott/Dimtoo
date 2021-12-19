using System;
using System.IO;
using System.Collections;
using System.Diagnostics;
using Pile;
using System.Reflection;

using internal Dimtoo;

namespace Dimtoo
{
	[AttributeUsage(.Struct|.Enum, .AlwaysIncludeTarget | .ReflectAttribute, ReflectUser = .AllMembers, AlwaysIncludeUser = .IncludeAllMethods | .AssumeInstantiated)]
	struct SerializableAttribute : Attribute, IComptimeTypeApply
	{
		[Comptime]
		public void ApplyToType(Type type)
		{
			Compiler.EmitTypeBody(type, """
				static this
				{
					let name = new System.String();
					Dimtoo.ComponentSerializer.[System.FriendAttribute]TypeToString!(typeof(Self), name);
					if (!Dimtoo.ComponentSerializer.serializableStructs.ContainsKey(name))
						Dimtoo.ComponentSerializer.serializableStructs.Add(name, typeof(Self));
					else System.Runtime.FatalError("Component name already taken");
				}
				""");
		}
	}

	[AttributeUsage(.Field, .ReflectAttribute)]
	struct NoSerializeAttribute : Attribute {}

	static class ComponentSerializer
	{
		public static Dictionary<String, Type> serializableStructs = new .() ~ DeleteDictionaryAndKeys!(_);

		static mixin TypeToString(Type type, String buffer)
		{
			let name = type.GetFullName(.. scope .(64));
			let namespaceLen = name.LastIndexOf('.');
			name.Remove(0, namespaceLen + 1);
			if (name.Contains("void"))
			{
				name.Append('_');
				type.Size.ToString(name);
			}
			buffer.Append(name);
		}

		static mixin VariantDataIsZero(Variant val)
		{
			bool isZero = true;
			for (var i < val.VariantType.Size)
				if (((uint8*)val.DataPtr)[i] != 0)
					isZero = false;
			isZero
		}

		static mixin RemoveTrailingComma(String buffer)
		{
			if (buffer.EndsWith(",\n"))
				buffer.RemoveFromEnd(2);
		}

		public static void SerializeScene(Scene scene, String buffer, bool exactEntity = true, bool includeDefault = false)
		{
			buffer.Append("[\n");

			Entity[] ent = null;
			if (!exactEntity)
			{
				// For this to work, we need a predictable order
				ent = scene.[Friend]entMan.[Friend]livingEntities.CopyTo(.. scope Entity[scene.[Friend]entMan.[Friend]livingEntities.Count]);
				for (let entity in ent)
				{
					SerializeEntity(scene, entity, buffer, ent, exactEntity, includeDefault);
					buffer.Append(",\n");
				}
			}
			else
			{
				for (let entity in scene.EnumerateEntities())
				{
					SerializeEntity(scene, entity, buffer, .(), exactEntity, includeDefault);
					buffer.Append(",\n");
				}
			}

			RemoveTrailingComma!(buffer);

			buffer.Append("\n]");
		}

		public static void SerializeGroup(Scene scene, Entity[] entities, String buffer, bool exactEntity = true, bool includeDefault = false)
		{
			buffer.Append("[\n");

			for (let entity in entities)
			{
				if (!scene.EntityLives(entity))
					continue;

				SerializeEntity(scene, entity, buffer, exactEntity ? .() : entities, exactEntity, includeDefault);
				buffer.Append(",\n");
			}

			RemoveTrailingComma!(buffer);

			buffer.Append("\n]");
		}

		static void SerializeEntity(Scene scene, Entity e, String buffer, Span<Entity> entities, bool exactEntity, bool includeDefault)
		{
			if (exactEntity)
				buffer.Append(scope $"{e}: [\n");
			else buffer.Append("[\n");

			for (let entry in scene.compMan.[Friend]componentArrays) // TODO: more general interface!
				if (entry.value.array.GetSerializeData(e, let data))
				{
					let oldLen = buffer.Length;
					TypeToString!(entry.key, buffer);
					buffer.Append(": ");

					if (SerializeStruct(entry.key, Variant.CreateReference(entry.key, data.Ptr), buffer, entities, includeDefault))
						buffer.Append(",\n");
					else buffer.RemoveFromEnd(buffer.Length - oldLen); // Remove what we already wrote again
				}

			RemoveTrailingComma!(buffer);

			buffer.Append("\n]");
		}

		static bool SerializeStruct(Type structType, Variant structVal, String buffer, Span<Entity> entities, bool includeDefault)
		{
			var structVal;
			Debug.Assert(structType.IsStruct);

			// All relevant pile types have reflection forced in build settings of Dimtoo, so don't check them here! (unless they obviously have no reflection info -> fieldCount)
			if ((!structType.GetFullName(.. scope .()).StartsWith("Pile.") || structType.FieldCount == 0) && structType.FieldCount == 0 && !structType.HasCustomAttribute<SerializableAttribute>())
			{
				Log.Debug(scope $"Struct {structType} is not marked as [Serializable] and will not be included");
				return false;
			}

			buffer.Append("{\n");

			for (let m in structType.GetFields(.Public|.Instance))
			{
				// TODO: unions!
				if ((m.FieldType.IsEnum && m.FieldType.IsUnion) || m.FieldType.IsPointer || m.FieldType.IsObject && !m.FieldType is SizedArrayType && m.FieldType != typeof(String)
					|| m.GetCustomAttribute<NoSerializeAttribute>() case .Ok) // If field has NoSerialize, skip!
					continue;

				Variant val = Variant.CreateReference(m.FieldType, ((uint8*)structVal.DataPtr) + m.MemberOffset);

				if (!includeDefault && VariantDataIsZero!(val))
					continue;

				let oldLen = buffer.Length;
				buffer.Append(m.Name);
				buffer.Append("=");

				let mention = SerializeValue(ref val, buffer, entities, includeDefault);

				if (!mention)
				{
					// Revert to previous state, just don't mention this field!
					buffer.RemoveFromEnd(buffer.Length - oldLen);
					continue;
				}

				buffer.Append(",\n");
			}

			RemoveTrailingComma!(buffer);

			if (!buffer.EndsWith("{\n"))
				buffer.Append("\n}");
			else
			{
				// Do <Name>{} on empty stuff
				buffer.RemoveFromEnd(1);
				buffer.Append('}');
			}

			return true;
		}

		static bool SerializeValue(ref Variant val, String buffer, Span<Entity> entities, bool includeDefault, bool smallBool = false)
		{
			Type fieldType = val.VariantType;

			if (fieldType.IsPointer || fieldType.IsObject && !fieldType is SizedArrayType && fieldType != typeof(String))
				return false; // Don't serialize objects or pointers
			else if (fieldType.IsInteger ||
				fieldType.IsTypedPrimitive && fieldType.UnderlyingType.IsInteger)
			{
				switch (fieldType)
				{
				case typeof(int8), typeof(int16), typeof(int32), typeof(int64), typeof(int):
					int64 integer = 0;
					Span<uint8>((uint8*)val.DataPtr, fieldType.Size).CopyTo(Span<uint8>((uint8*)&integer, fieldType.Size));
					integer.ToString(buffer);
				default: // unsigned
					uint64 integer = 0;
					Span<uint8>((uint8*)val.DataPtr, fieldType.Size).CopyTo(Span<uint8>((uint8*)&integer, fieldType.Size));
					integer.ToString(buffer);
				}
			}
			else if (fieldType.IsFloatingPoint
				|| fieldType.IsTypedPrimitive && fieldType.UnderlyingType.IsFloatingPoint)
			{
				switch (fieldType)
				{
				case typeof(float):
					let f = val.Get<float>();
					f.ToString(buffer);
				case typeof(double):
					let d = val.Get<double>();
					d.ToString(buffer);
				default: Debug.FatalError();
				}
			}
			else if (fieldType == typeof(bool))
			{
				if (!smallBool)
					val.Get<bool>().ToString(buffer);
				else
				{
					if (val.Get<bool>())
						buffer.Append('1');
					else buffer.Append('0');
				}
			}
			else if (fieldType is SizedArrayType)
			{
				buffer.Append("[\n");

				let t = (SizedArrayType)fieldType;
				let count = t.ElementCount;
				let arrType = t.UnderlyingType;

				var zeroIndex = 0, cutBufferLen = buffer.Length;
				var ptr = (uint8*)val.DataPtr;
				for (let i < count)
				{
					var arrVal = Variant.CreateReference(arrType, ptr);

					if (SerializeValue(ref arrVal, buffer, entities, includeDefault, true))
					{
						if (!(arrType.IsPrimitive || arrType.IsTypedPrimitive))
							buffer.Append(",\n");
						else buffer.Append(", "); // Just put primitives in one line!
					}
					else return false; // Just don't serialize the array at all!

					if (!includeDefault && !VariantDataIsZero!(arrVal))
					{
						zeroIndex = i + 1; // Next one might be
						cutBufferLen = buffer.Length; // In that case, cut here
					}

					ptr += arrType.Size;
				}

				// Cut the array when all thats left is default
				if (!includeDefault && zeroIndex < count)
					buffer.RemoveFromEnd(buffer.Length - cutBufferLen);

				if (buffer[buffer.Length - 2] == ',')
					buffer.RemoveFromEnd(2); // Remove last ", " or ",\n"

				buffer.Append("\n]");
			}
			else if (fieldType.IsEnum)
			{
				if (fieldType.IsUnion)
				{
					Log.Debug("Cannot serialize union enum");
				}
				else
				{
					int64 value = 0;
					Span<uint8>((uint8*)val.DataPtr, fieldType.Size).CopyTo(Span<uint8>((uint8*)&value, fieldType.Size));
					Enum.EnumToString(fieldType, buffer, value);
				}
			}
			else if (fieldType == typeof(String)
				|| fieldType == typeof(StringView))
			{
				String nameString;
				if (fieldType == typeof(StringView))
				{
					let view = val.Get<StringView>();

					if (view.Ptr == null)
						return false;

					nameString = scope:: .(view);
				}
				else
				{
					nameString = val.Get<String>();

					if (nameString == null) // no need to serialize, value is default
						return false;
				}

				String.QuoteString(&nameString[0], nameString.Length, buffer);
			}
			else if (fieldType == typeof(Entity))
			{
				Entity entity = .Invalid;
				Span<uint8>((uint8*)val.DataPtr, fieldType.Size).CopyTo(Span<uint8>((uint8*)&entity, sizeof(Entity)));
				if (entities.Ptr != null && entity != .Invalid)
				{
					// If we don't keep the id's of entities, convert those to ref indices in the save data
					// entities.Ptr will only not be null, when we do not keep entity ids

					bool found = false;
					for (let i < entities.Length)
						if (entities[i] == entity)
						{
							found = true;

							// Instead reference that the value is the id of the 'x'th entity we're saving
							buffer.Append('&');
							i.ToString(buffer);
						}

					if (!found)
					{
						Log.Warn("A serialized component contains a reference to an entity not included in the save. Since the save does not include exact entity ids, this field will not be serialized!");
						return false;
					}
				}
				else entity.ToString(buffer);
			}
			else if (let t = fieldType as SpecializedGenericType && t.UnspecializedType == typeof(Asset<>))
			{
				if (fieldType.GetField("name") case .Ok(let nameField))
				{
					// Just serialize the name as the whole asset.. other stuff is just internal runtime info!
					Variant nameVal = Variant.CreateReference(nameField.FieldType, ((uint8*)val.DataPtr) + nameField.MemberOffset);
					return SerializeValue(ref nameVal, buffer, entities, includeDefault, smallBool);
				}
				else
				{
					Log.Warn("Couldn't serialize asset");
					return false;
				}
			}
			else if (fieldType.IsStruct)
			{
				return SerializeStruct(fieldType, val, buffer, entities, includeDefault);
			}
			else
			{
				Log.Debug($"Couldn't serialize field of type {fieldType.GetName(.. scope .())}");
				return false;
			}

			return true;
		}

		static mixin ForceEat(char8 expect, ref StringView buffer)
		{
			if (buffer.StartsWith(expect))
				buffer.RemoveFromStart(1);
			else LogErrorReturn!(scope $"Unexpected token: {buffer[0]} instead of {expect}");
		}

		static mixin EatSpace(ref StringView buffer)
		{
			var i = 0;
			for (; i < buffer.Length; i++)
			{
				if (!buffer[i].IsWhiteSpace)
					break;
			}

			buffer.RemoveFromStart(i);
		}

		public static Result<void> Deserialize(Scene scene, StringView buffer, List<Entity> createdEntities = null)
		{
			var buffer;
			EatSpace!(ref buffer);

			ForceEat!('[', ref buffer);

			EatSpace!(ref buffer);

			let deserializedEntities = scope List<Entity>();
			let deferResolveEntityRefs = scope List<(int indexRef, Variant value)>();

			while ({
				EatSpace!(ref buffer);
				buffer[0] != ']'
				})
			{
				Try!(DeserializeEntity(scene, ref buffer, deserializedEntities, deferResolveEntityRefs));

				EatSpace!(ref buffer);

				if (buffer[0] == ',')
					buffer.RemoveFromStart(1);
			}

			ForceEat!(']', ref buffer);

			// Only added to when we have entity refs!
			if (deferResolveEntityRefs.Count > 0)
			{
				// This list should be filled with at least something, since clearly values were read
				// And new entities should have been created
				Debug.Assert(deserializedEntities.Count != 0);

				// Fill in all these values with the Entity values we get from the array
				for (var set in deferResolveEntityRefs)
					*((Entity*)set.value.DataPtr) = deserializedEntities[set.indexRef];
			}

			if (createdEntities != null)
				createdEntities.AddRange(deserializedEntities);

			return .Ok;
		}

		static Result<void> DeserializeEntity(Scene scene, ref StringView buffer, List<Entity> deserializedEntities, List<(int indexRef, Variant value)> deferResolveEntityRefs)
		{
			EatSpace!(ref buffer);

			Entity e;
			if (buffer[0].IsNumber)
			{
				var numLen = 1;
				while (buffer.Length > numLen + 1 && buffer[numLen].IsNumber)
					numLen++;

				if (uint.Parse(.(&buffer[0], numLen)) case .Ok(let val))
				{
					e = (Entity)val;
					if (e >= MAX_ENTITIES)
						LogErrorReturn!("Entity out of range");

					buffer.RemoveFromStart(numLen);
				}
				else LogErrorReturn!("Failed to parse entity id");

				if (scene.CreateSpecificEntitiy(e) case .Err)
					return LogErrorReturn!("Requested entity already exists");

				EatSpace!(ref buffer);
				ForceEat!(':', ref buffer);
				EatSpace!(ref buffer);
			}
			else
			{
				// Just take any available entity
				e = scene.CreateEntity();
			}

			deserializedEntities.Add(e);

			ForceEat!('[', ref buffer);

			while ({
				EatSpace!(ref buffer);
				buffer[0] != ']'
				})
			{
				// Get type from name
				Try!(DeserializeComponentType(let componentType, ref buffer));

				let structMemory = scene.ReserveComponent(e, componentType);

				EatSpace!(ref buffer);
				ForceEat!(':', ref buffer);

				// Fill in type from body
				EatSpace!(ref buffer);
				if (!buffer.StartsWith("{}"))
				{
					Try!(DeserializeStructBody(scene, componentType, structMemory, ref buffer, deferResolveEntityRefs));
				}
				else buffer.RemoveFromStart(2); // just empty brackets, nothing to do

				EatSpace!(ref buffer);

				if (buffer[0] == ',')
					buffer.RemoveFromStart(1);
			}

			ForceEat!(']', ref buffer);

			return .Ok;
		}

		static Result<void> DeserializeComponentType(out Type structType, ref StringView buffer)
		{
			EatSpace!(ref buffer);

			{
				var genericDepth = 0;
				var nameLen = 0;
				NAMEGET:for (; nameLen < buffer.Length; nameLen++)
				{
					let char = buffer[nameLen];
					if (!char.IsLetterOrDigit && char != '.' && char != '_')
					{
						switch (char)
						{
						case '<':
							genericDepth++;
						case '>':
							genericDepth--;
							Debug.Assert(genericDepth >= 0);
						default:
							if (genericDepth == 0)
								break NAMEGET;
						}
					}
				}

				let name = buffer.Substring(0, nameLen);
				buffer.RemoveFromStart(nameLen);

				if (!serializableStructs.TryGetValue(scope String(name), out structType))
					LogErrorReturn!(scope $"Unrecognized component name: {name} (not marked as [Serializable]?)");
			}

			Debug.Assert(structType != null);

			return .Ok;
		}

		static Result<void> DeserializeStructBody(Scene scene, Type structType, Span<uint8> structTargetMem, ref StringView buffer, List<(int indexRef, Variant value)> deferResolveEntityRefs)
		{
			ForceEat!('{', ref buffer);

			Debug.Assert(structTargetMem.Length == structType.Size); // Size miss-match

			Variant structVal = Variant.CreateReference(structType, structTargetMem.Ptr);

			while ({
				EatSpace!(ref buffer);
				buffer[0] != '}'
				})
			{
				// Get field name
				var nameLen = 0;
				for (; nameLen < buffer.Length; nameLen++)
					if (!buffer[nameLen].IsLetterOrDigit && buffer[nameLen] != '_')
						break;

				let name = buffer.Substring(0, nameLen);
				buffer.RemoveFromStart(nameLen);

				EatSpace!(ref buffer);
				ForceEat!('=', ref buffer);
				EatSpace!(ref buffer);

				FieldInfo fieldInfo;
				switch (structType.GetField(scope .(name)))
				{
				case .Ok(let val):
					fieldInfo = val;
				case .Err:
					continue; // Field does not exist
				}

				Variant fieldVal = Variant.CreateReference(fieldInfo.FieldType, ((uint8*)structVal.DataPtr) + fieldInfo.MemberOffset);

				Try!(DeserializeValue(scene, ref fieldVal, ref buffer, deferResolveEntityRefs));

				EatSpace!(ref buffer);

				if (buffer[0] == ',')
					buffer.RemoveFromStart(1);
			}

			ForceEat!('}', ref buffer);

			return .Ok;
		}

		static Result<void> DeserializeValue(Scene scene, ref Variant val, ref StringView buffer, List<(int indexRef, Variant value)> deferResolveEntityRefs)
		{
			Type fieldType = val.VariantType;

			if (fieldType.IsInteger
				|| fieldType.IsTypedPrimitive && fieldType.UnderlyingType.IsInteger)
			{
				var numLen = 0;
				while (buffer.Length > numLen + 1 && buffer[numLen].IsNumber || buffer[numLen] == '-')
					numLen++;

				if (numLen == 0)
					LogErrorReturn!("Expected integer literal");

				switch (fieldType)
				{
				case typeof(int8), typeof(int16), typeof(int32), typeof(int64), typeof(int):
					if (int64.Parse(.(&buffer[0], numLen)) case .Ok(var num))
						Internal.MemCpy(val.DataPtr, &num, fieldType.Size);
					else LogErrorReturn!("Failed to parse integer");
				default: // unsigned
					if (uint64.Parse(.(&buffer[0], numLen)) case .Ok(var num))
						Internal.MemCpy(val.DataPtr, &num, fieldType.Size);
					else LogErrorReturn!("Failed to parse integer");
				}

				buffer.RemoveFromStart(numLen);
			}
			else if (fieldType.IsFloatingPoint
				|| fieldType.IsTypedPrimitive && fieldType.UnderlyingType.IsFloatingPoint)
			{
				var numLen = 0;
				while (buffer.Length > numLen + 1 && buffer[numLen].IsNumber || buffer[numLen] == '.' || buffer[numLen] == '-' || buffer[numLen] == 'e')
					numLen++;

				if (numLen == 0)
					LogErrorReturn!("Expected floating point literal");

				switch (fieldType)
				{
				case typeof(float):
					if (float.Parse(.(&buffer[0], numLen)) case .Ok(let num))
						*(float*)val.DataPtr = num;
					else LogErrorReturn!("Failed to parse floating point");
				case typeof(double):
					if (double.Parse(.(&buffer[0], numLen)) case .Ok(let num))
						*(double*)val.DataPtr = num;
					else LogErrorReturn!("Failed to parse floating point");
				default:
					LogErrorReturn!("Unexpected floating point");
				}

				buffer.RemoveFromStart(numLen);
			}
			else if (fieldType == typeof(bool))
			{
				if (buffer.StartsWith(bool.TrueString, .OrdinalIgnoreCase))
				{
					*(bool*)val.DataPtr = true;
					buffer.RemoveFromStart(bool.TrueString.Length);
				}
				else if (buffer[0] == '1')
				{
					*(bool*)val.DataPtr = true;
					buffer.RemoveFromStart(1);
				}
				else if (buffer.StartsWith(bool.FalseString, .OrdinalIgnoreCase))
				{
					// Is already 0, sooOOo nothing to do here
					buffer.RemoveFromStart(bool.FalseString.Length);
				}
				else if (buffer[0] == '0')
				{
					// Is already 0, sooOOo nothing to do here
					buffer.RemoveFromStart(1);
				}
				else LogErrorReturn!("Failed to parse bool");
			}
			else if (fieldType is SizedArrayType)
			{
				ForceEat!('[', ref buffer);
				EatSpace!(ref buffer);

				let t = (SizedArrayType)fieldType;
				let count = t.ElementCount;
				let arrType = t.UnderlyingType;

				var i = 0;
				var ptr = (uint8*)val.DataPtr;
				while ({
					EatSpace!(ref buffer);
					buffer[0] != ']'
					})
				{
					if (i >= count)
						LogErrorReturn!("Too many elements given in array");

					var arrVal = Variant.CreateReference(arrType, ptr);
					Try!(DeserializeValue(scene, ref arrVal, ref buffer, deferResolveEntityRefs));

					ptr += arrType.Size;
					i++;

					EatSpace!(ref buffer);

					if (buffer[0] == ',')
						buffer.RemoveFromStart(1);
				}
	
				ForceEat!(']', ref buffer);
			}
			else if (fieldType.IsEnum)
			{
				// Get enum value
				var enumLen = 0, isNumber = true;
				for (; enumLen < buffer.Length; enumLen++)
					if (!buffer[enumLen].IsDigit)
					{
						if (!buffer[enumLen].IsLetter && buffer[enumLen] != '_')
							break;
						else isNumber = false;
					}

				if (enumLen == 0)
					LogErrorReturn!("Expected enum value");

				let enumVal = buffer.Substring(0, enumLen);
				buffer.RemoveFromStart(enumLen);

				if (isNumber)
				{
					if (fieldType.IsSigned)
					{
						if (int64.Parse(enumVal) case .Ok(var num))
							Internal.MemCpy(val.DataPtr, &num, fieldType.Size);
						else LogErrorReturn!("Failed to parse enum integer");
					}
					else
					{
						if (uint64.Parse(enumVal) case .Ok(var num))
							Internal.MemCpy(val.DataPtr, &num, fieldType.Size);
						else LogErrorReturn!("Failed to parse enum integer");
					}
				}
				else
				{
					FINDFIELD:do
					{
						let typeInst = (TypeInstance)fieldType;
						for (let field in typeInst.GetFields())
						{
							if (enumVal.Equals(field.[Friend]mFieldData.mName, false))
							{
								Internal.MemCpy(val.DataPtr, &field.[Friend]mFieldData.mData, fieldType.Size);
								break FINDFIELD;
							}
						}

						LogErrorReturn!("Failed to parse enum string");
					}
				}
			}
			else if (fieldType == typeof(String)
				|| fieldType == typeof(StringView))
			{
				if (buffer[0] != '"')
					LogErrorReturn!("String must start with '\"'");

				// Find terminating "
				int endIdx = -1;
				bool isEscape = false;
				for (let c in buffer[1...])
				{
					if (c == '"' && !isEscape)
					{
						endIdx = @c.Index;
						break;
					}	

					if (c == '\\')
						isEscape = true;
					else isEscape = false;
				}
				if (endIdx == -1)
					LogErrorReturn!("Unterminated string in asset notation");

				// Manage string!
				var nameStr = String.UnQuoteString(&buffer[0], endIdx + 2, .. scope .());
				if (scene.managedStrings.Contains(nameStr))
				{
					Debug.Assert(!scene.managedStrings.TryAdd(nameStr, let existantStr));

					nameStr = *existantStr;
				}
				else
				{
					// Allocate new one, doesnt currently exist!
					nameStr = scene.managedStrings.Add(.. new .(nameStr));
				}

				if (fieldType == typeof(StringView))
				{
					// Make and copy stringView
					var strVal = (StringView)nameStr;
					Internal.MemCpy(val.DataPtr, &strVal, sizeof(StringView));
				}
				else
				{
					// Copy pointer to string
					Internal.MemCpy(val.DataPtr, &nameStr, sizeof(int));
				}

				buffer.RemoveFromStart(endIdx + 2);
			}
			else if (fieldType == typeof(Entity))
			{
				bool isRef = false;
				if (buffer[0] == '&')
				{
					isRef = true;
					buffer.RemoveFromStart(1);
				}

				var numLen = 0;
				while (buffer.Length > numLen + 1 && buffer[numLen].IsNumber || buffer[numLen] == '-')
					numLen++;

				if (numLen == 0)
					LogErrorReturn!("Expected integer literal");

				if (!isRef)
				{
					if (uint64.Parse(.(&buffer[0], numLen)) case .Ok(let num))
					{
						Entity ent = (uint16)num;
						Internal.MemCpy(val.DataPtr, &ent, sizeof(Entity));
					}
					else LogErrorReturn!("Failed to parse integer");
				}
				else
				{
					if (uint64.Parse(.(&buffer[0], numLen)) case .Ok(var num))
					{
						// Resolve these later when we have the full list of newly created entities and their ids
						deferResolveEntityRefs.Add(((.)num, val));
					}
					else LogErrorReturn!("Failed to parse reference");
				}

				buffer.RemoveFromStart(numLen);
			}
			else if (let t = fieldType as SpecializedGenericType && t.UnspecializedType == typeof(Asset<>))
			{
				if (fieldType.GetField("name") case .Ok(let nameField))
				{
					Variant nameVal = Variant.CreateReference(nameField.FieldType, ((uint8*)val.DataPtr) + nameField.MemberOffset);

					// TODO: would be nice to properly call constructor?

					// Fill in name field!
					return DeserializeValue(scene, ref nameVal, ref buffer, deferResolveEntityRefs);
				}
				else LogErrorReturn!("Couldn't deserialize asset");
			}
			else if (fieldType.IsStruct)
			{
				Try!(DeserializeStructBody(scene, fieldType, .((uint8*)val.DataPtr, fieldType.Size), ref buffer, deferResolveEntityRefs));
			}
			else LogErrorReturn!("Cannot handle value");

			return .Ok;
		}
	}
}
