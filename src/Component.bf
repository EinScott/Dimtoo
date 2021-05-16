using System;
using System.Collections;

namespace Dimtoo
{
	[Reflect(.Type),StaticInitPriority(-1)]
	abstract class Component
	{
		static List<Type> updateParticipants = new .() ~ delete _;
		static List<Type> renderParticipants = new .() ~ delete _;

		static this()
		{
			List<int> priorities = scope .();

			// Reflection magic
			for (let type in Type.Types)
			{
				if (!type.IsObject || type.IsBoxed || type.IsArray || !type.IsSubtypeOf(typeof(Component)) || type == typeof(Component))
					continue;

				var it = type;
				var hasUpdate = false, hasRender = false, hasPriority = false, updatePriority = 0;
				while (true)
				{
					if (!hasUpdate && it.HasCustomAttribute<UpdateAttribute>())
						hasUpdate = true;

					if (!hasRender && it.HasCustomAttribute<RenderAttribute>())
						hasRender = true;

					if (!hasPriority && type.GetCustomAttribute<PriorityAttribute>() case .Ok(let val))
					{
						updatePriority = val.updatePriority;
						hasPriority = true; // Only take the one further up the inheritance tree
					}

					if (it.BaseType == typeof(Component))
						break;

					it = it.BaseType;
				}

				if (hasUpdate)
				{
					var insert = 0;
					if (priorities.Count == 0)
						priorities.Add(updatePriority);
					else
					{
						if (updatePriority < priorities.Back)
						{
							for (let pri in priorities)
							{
								if (updatePriority > pri)
									break;
								insert++;
							}
						}
						else
						{
							insert = priorities.Count;
							priorities.Add(updatePriority);
						}
					}

					updateParticipants.Insert(insert, type);
				}

				if (hasRender)
					renderParticipants.Add(type);
			}
		}

		internal Component nextOnEntity;

		public ref Entity Entity { [Inline]get; internal set; }

		protected virtual void Attach() {}

		protected virtual void Update() {}
		protected virtual void Render() {}
	}
}
