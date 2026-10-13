float scale = 10;
int rows,cols;
float[][] flowField;

float[][] smoothedFlowField;
int smoothingIterationCount = 5;

float[][] targetFlowField;
float noiseIterationAmount = 0.001;
float noiseIteration = 0;
float fieldMorphSpeed = 0.01;

float noiseScale = 0.01;
float noiseWeight = 0.4;
float sineWaveWeight = 0.15;
float lineSeedSpacing = 12;
float lineStrokeWeightMin = 1;
float lineStrokeWeightMax = 5;

int circleObstacleCount = 2;
CircleObstacle[] circleObstacles;

LineDrawer[] lineDrawers;

class CircleObstacle {
  public int xPos,yPos;
  public int radius;
}

class LinePoint {
  PVector position;

  LinePoint(float x, float y) {
    position = new PVector(x, y);
  }

  void display() {
    noStroke();
    fill(0);
    circle(position.x, position.y, 5);
  }
}

class LineDrawer {
  String id;
  PVector startPosition;
  ArrayList<LinePoint> linePoints;

  int integrationStep = 1; // amount of pixels each line will be

  LineDrawer(String _id, float x, float y) {
    id = _id;
    startPosition = new PVector(x, y);
    linePoints = new ArrayList<LinePoint>();
  }

  void update() {
    // clear all line points
    linePoints.clear();

    // create line points by following a curve traced by the flow field
    PVector currentPosition = new PVector(startPosition.x, startPosition.y);
    while (currentPosition.x >= 0 && currentPosition.x <= width && currentPosition.y >= 0 && currentPosition.y <= height) {
      linePoints.add(new LinePoint(currentPosition.x, currentPosition.y));

      PVector newPosition = rk4Step(currentPosition, integrationStep);

      currentPosition.x = newPosition.x;
      currentPosition.y = newPosition.y;
    }
  }

  void display() {
    // draw lines for all created line points
    float noiseScale = 0.01;
    for (int i = 0; i < linePoints.size(); i++) {
      LinePoint linePoint = linePoints.get(i);
      // linePoint.display();
      if (i > 0) {
        LinePoint linePoint1 = linePoints.get(i - 1);
        LinePoint linePoint2 = linePoint;
        int col = constrain(int(linePoint.position.x / scale), 0, cols - 1);
        int row = constrain(int(linePoint.position.y / scale), 0, rows - 1);
        float strokeWeightValue = map(/*noiseWeight * 1.2 * */noise(row * noiseScale + noiseIteration * i * 0.001, col * noiseScale + noiseIteration * i * 0.001)/*+ sineWaveWeight * 1.5 * sin(row * (noiseScale * 5))*/, 0, 1, lineStrokeWeightMin, lineStrokeWeightMax);
        stroke(0);
        strokeWeight(strokeWeightValue);
        line(linePoint1.position.x, linePoint1.position.y, linePoint2.position.x, linePoint2.position.y);
      }
    }
  }
}

void setup() {
  size(360, 640);
  
  rows = int(height/scale);
  cols = int(width/scale);
  
  circleObstacles = new CircleObstacle[circleObstacleCount];
  generateCircleObstacles();
  

  targetFlowField = new float[rows][cols];
  smoothedFlowField = new float[rows][cols];
  flowField = new float[rows][cols];
  generateFlowField();
  morphFlowField();

  generateLineDrawers();
}

void draw() {
  background(255);
  generateFlowField();
  morphFlowField();

  // drawFlowField();
  // drawCircleObstacles();
  // drawLineField();
  drawLines();

  noiseIteration += noiseIterationAmount;
}

/** Generation Functions **/

void generateCircleObstacles() {
  CircleObstacle firstCircle = new CircleObstacle();
  CircleObstacle secondCircle = new CircleObstacle();
  int radiusBuffer = 7;
  int positionalBuffer = 10;
  
  firstCircle.radius = int(random(radiusBuffer, cols / 2 - radiusBuffer)) + 1;
  firstCircle.xPos = int(random(0 + firstCircle.radius, cols / 2 - firstCircle.radius));
  firstCircle.yPos = int(random(positionalBuffer + firstCircle.radius, rows / 2 - firstCircle.radius));
  
  secondCircle.radius = int(random(radiusBuffer, cols / 2 - radiusBuffer)) + 1;
  secondCircle.xPos = int(random(cols / 2 + secondCircle.radius, cols - secondCircle.radius));
  secondCircle.yPos = int(random(rows / 2 + secondCircle.radius, rows - secondCircle.radius - positionalBuffer));
  
  circleObstacles[0] = firstCircle;
  circleObstacles[1] = secondCircle;
  
  print("Circle 1 radius: ", firstCircle.radius, "\n");
  print("Circle 2 radius: ", secondCircle.radius, "\n");
}

void generateFlowField() {
  for (int i = 0; i < rows; i++) {
    for (int j = 0; j < cols; j++) {
      targetFlowField[i][j] = generateFlowFieldAngle(i, j);
      for (int c = 0; c < circleObstacleCount; c++) {
        targetFlowField[i][j] = calculateObstacleRepulsion(c, i, j, targetFlowField[i][j]);
      }
    }
  }

  for (int s = 0; s < smoothingIterationCount; s++) {
    for (int i = 0; i < rows; i++) {
      for (int j = 0; j < cols; j++) {
        smoothedFlowField[i][j] = calculateNeighborSmoothing(i, j, targetFlowField[i][j]);
      }
    }
    // copy smoothed flow field into flow field
    for (int i = 0; i < rows; i++) {
      targetFlowField[i] = smoothedFlowField[i].clone();
    }
  }
}

float generateFlowFieldAngle(float row, float col) {
  float flowFieldAngle = map(noiseWeight * noise(row * noiseScale + noiseIteration, col * noiseScale + noiseIteration) + sineWaveWeight * sin(row * (noiseScale * 5)), 0, 1, 0, 2 * PI);
  return flowFieldAngle;
}

float calculateObstacleRepulsion(int circleIndex, int row, int col, float flowFieldAngle) {
  CircleObstacle circle = circleObstacles[circleIndex];
  float deltaX = col - circle.xPos;
  float deltaY = row - circle.yPos;
  float distance = sqrt(deltaX * deltaX + deltaY * deltaY);
  float influenceMultiplier = 1.05;
  float influence = circle.radius * influenceMultiplier;
  if (distance < influence) {
    // angle pointing away from the obstacle
    float radialAngle = atan2(deltaY, deltaX);
    
    // two possible directions around the obstacle
    float tangentAngle1 = radialAngle + PI / 2;
    float tangentAngle2 = radialAngle - PI / 2;
    float tangentAngle;
    
    // choose the tangent closest to the original flow direction
    float difference1 = angleDifference(flowFieldAngle, tangentAngle1);
    float difference2 = angleDifference(flowFieldAngle, tangentAngle2);
    if (abs(difference1) < abs(difference2)) {
      tangentAngle = tangentAngle1;
    } else {
      tangentAngle = tangentAngle2;
    }
    
    // 0 = no influence, 1 = maximum influence
    float strength = constrain(
      (influence - distance) / (influence - circle.radius / 2),
      0,
      1
    );
    
    strength = strength * strength * (3 - 2 * strength);

    // blend the angles
    flowFieldAngle = lerpAngle(
      flowFieldAngle,
      tangentAngle,
      strength
    );
  }
  
  return flowFieldAngle;
}

float calculateNeighborSmoothing(int row, int col, float flowFieldAngle) {
  int neighborCount = 8;
  float smoothingStrength = 0.15;
  
  PVector[] neighborRelativeCoordinates = new PVector[neighborCount];
  neighborRelativeCoordinates[0] = new PVector(-1, -1);
  neighborRelativeCoordinates[1] = new PVector(0, -1);
  neighborRelativeCoordinates[2] = new PVector(1, -1);
  neighborRelativeCoordinates[3] = new PVector(1, 0);
  neighborRelativeCoordinates[4] = new PVector(1, 1);
  neighborRelativeCoordinates[5] = new PVector(0, 1);
  neighborRelativeCoordinates[6] = new PVector(-1, 1);
  neighborRelativeCoordinates[7] = new PVector(-1, 0);
  
  float sumX = 0;
  float sumY = 0;

  // for each neighbor
  for (int n = 0; n < neighborCount; n++) {
    if (
      col + neighborRelativeCoordinates[n].x >= 0 && 
      row + neighborRelativeCoordinates[n].y >= 0 && 
      col + neighborRelativeCoordinates[n].x < cols && 
      row + neighborRelativeCoordinates[n].y < rows
    ) {
      PVector neighborCoordinates = new PVector(col + neighborRelativeCoordinates[n].x, row + neighborRelativeCoordinates[n].y);
      float neighborAngle = targetFlowField[int(neighborCoordinates.y)][int(neighborCoordinates.x)];
      sumX += cos(neighborAngle);
      sumY += sin(neighborAngle);
    }
  }

  float averageAngle = atan2(sumY, sumX);
  flowFieldAngle = lerpAngle(
    flowFieldAngle,
    averageAngle,
    smoothingStrength
  );
  
  return flowFieldAngle;
}

void morphFlowField() {
  for (int i = 0; i < rows; i++) {
    for (int j = 0; j < cols; j++) {
      flowField[i][j] = lerpAngle(
        flowField[i][j],
        targetFlowField[i][j],
        fieldMorphSpeed
      );
    }
  }
}

void generateLineDrawers() {
  ArrayList<LineDrawer> drawers = new ArrayList<LineDrawer>();
  for (float x = lineSeedSpacing / 2; x < width; x += lineSeedSpacing) {
    drawers.add(new LineDrawer("lid" + drawers.size(), x, 0));
    print("Creating line drawer " + drawers.size() + " at " + x + "\n");
  }
  lineDrawers = drawers.toArray(new LineDrawer[0]);
}

/** Draw Functions **/

void drawFlowField() {
  for (int i = 0; i < rows; i++) {
    for (int j = 0; j < cols; j++) {
      pushMatrix();
      translate(j*scale, i*scale); // row index is technically y value and col index is technically x value
      rotate(flowField[i][j]);
      strokeWeight(1);
      stroke(0, 255, 0);
      line(0, 0, scale * 0.5, 0);
      popMatrix();
    }
  }
}

void drawCircleObstacles() {
  for (int i = 0; i < circleObstacleCount; i++) {
    strokeWeight(5);
    stroke(255, 0, 0);
    circle(
      circleObstacles[i].xPos * scale,
      circleObstacles[i].yPos * scale,
      circleObstacles[i].radius * scale * 2
    );
  }
}

void drawLineField() {
  float x,y;
  float newX,newY;
  for (int i = 0; i < rows; i++) {
    x = i * scale;
    y = 0;
    while (x >= 0 && x < width && y >= 0 && y < height) {
      float angle = flowField[int(y / scale)][int(x / scale)];
      newX = x + scale * cos(angle);
      newY = y + scale * sin(angle);
      strokeWeight(1);
      stroke(0, 0, 255);
      line(x, y, newX, newY);
      x = newX;
      y = newY;
    }
  }
}

void drawLines() {
  for (int i = 0; i < lineDrawers.length; i++) {
    lineDrawers[i].update();
    lineDrawers[i].display();
  }
}

/** Utility Functions **/

float angleDifference(float a, float b) {
  return atan2(
    sin(b - a),
    cos(b - a)
  );
}

float lerpAngle(float a, float b, float t) {
  float difference = angleDifference(a, b);
  return a + difference * t;
}

PVector sampleFlow(float x, float y) {
  float gx = constrain(x / scale, 0, cols - 1.001);
  float gy = constrain(y / scale, 0, rows - 1.001);

  int x0 = int(gx);
  int y0 = int(gy);
  int x1 = min(x0 + 1, cols - 1);
  int y1 = min(y0 + 1, rows - 1);

  float tx = gx - x0;
  float ty = gy - y0;

  float a00 = flowField[y0][x0];
  float a10 = flowField[y0][x1];
  float a01 = flowField[y1][x0];
  float a11 = flowField[y1][x1];

  float vx =
    cos(a00) * (1-tx) * (1-ty) +
    cos(a10) * tx * (1-ty) +
    cos(a01) * (1-tx) * ty +
    cos(a11) * tx * ty;

  float vy =
    sin(a00) * (1-tx) * (1-ty) +
    sin(a10) * tx * (1-ty) +
    sin(a01) * (1-tx) * ty +
    sin(a11) * tx * ty;

  return new PVector(vx, vy).normalize();
}

PVector flowDirection(float x, float y) {
  PVector direction = sampleFlow(x, y);

  if (direction.magSq() > 0.000001) {
    direction.normalize();
  }

  return direction;
}

PVector rk4Step(PVector p, float h) {
  PVector k1 = flowDirection(p.x, p.y);

  PVector k2 = flowDirection(
    p.x + h * k1.x * 0.5,
    p.y + h * k1.y * 0.5
  );

  PVector k3 = flowDirection(
    p.x + h * k2.x * 0.5,
    p.y + h * k2.y * 0.5
  );

  PVector k4 = flowDirection(
    p.x + h * k3.x,
    p.y + h * k3.y
  );

  return new PVector(
    p.x + h * (k1.x + 2*k2.x + 2*k3.x + k4.x) / 6.0,
    p.y + h * (k1.y + 2*k2.y + 2*k3.y + k4.y) / 6.0
  );
}
