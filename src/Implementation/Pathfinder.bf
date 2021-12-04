using System;
using Pile;

namespace Dimtoo
{
	struct PathfinderComponent
	{
		public Entity referenceGrid;
		public Point2 startPoint;
		public Point2 endPoint;

		public bool regeneratePath;
		
		// HOW THE HELL DO WE STORE A PATH?
		// maybe just a limited/gradual generation?
		// -> could we even.. or would that require more space?
	}

	struct PathfinderObstacleComponent
	{
		// On everything that has this, we detect if it has a collisionBody or grid
		// then work with that
	}

	// TODO: when we optimize collisionSystem, we will probably have it make some datastructure of
	// entity by pos, and add an event to systems when they loose a component..
	// -> then make some sort of SpacialComponentSystem that gets just entities efficiently
	//    queried by position, AND THEN WE CAN USE IT HERE TOO, since we can construct a bounding box from startPoint
	//    and endPoint, and thus search obstacles just in that rect!

	class PathfinderSystem : ComponentSystem
	{

	}
}
