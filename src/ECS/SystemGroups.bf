using System;
using System.Collections;
using Pile;

namespace Dimtoo
{
	interface IRendererSystem
	{
		public float GetRenderLayer();
		public void Render(Batch2D batch);
	}

	class RenderSystemGroup
	{
		readonly List<IRendererSystem> renderSystems = new List<IRendererSystem>() ~ delete _;

		public void RegisterRenderSystem(IRendererSystem system)
		{
			if (!renderSystems.Contains(system))
				renderSystems.Add(system);
		}

		public void Render(Batch2D batch)
		{
			for (let rend in renderSystems)
			{
				batch.SetLayer((.)rend.GetRenderLayer());
				rend.Render(batch);
			}
		}
	}

	interface ITickSystem
	{
		public void Tick();
	}

	class TickSystemGroup
	{
		readonly List<ITickSystem> tickSystem = new List<ITickSystem>() ~ delete _;

		public void RegisterTickSystem(ITickSystem system)
		{
			if (!tickSystem.Contains(system))
				tickSystem.Add(system);
		}

		public void Tick()
		{
			for (let rend in tickSystem)
			{
				rend.Tick();
			}
		}
	}
}
