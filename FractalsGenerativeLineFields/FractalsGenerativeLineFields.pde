float scale = 10;
int rows,cols;
int visibleRows, visibleCols;

float[][] flowField;
float fieldOffsetX;
float fieldOffsetY;

float[][] smoothedFlowField;
int smoothingIterationCount = 50;

float[][] targetFlowField;
float noiseIterationAmount = 0.1;
float noiseIteration = 0;
float fieldMorphSpeed = 0.5;

float noiseScale = 0.01;
float noiseWeight = 0.4;
float sineWaveWeight = 0.15;
float lineSeedSpacing = 20;

float densityCellSize = 20;
int densityCols, densityRows;
float[][] lineDensity;
float densityRadius = 5;
float densityStrength = 20;
float densityInfluence = 0.7;
float noiseInfluence = 0.3;
float lineStrokeNoiseIterationAmount = 0.015;
float lineStrokeNoiseIteration = 0.2;
float lineStrokeWeightMin = 1;
float lineStrokeWeightMax = 25;
float strokeWeightSmoothing = 0.1;

int circleObstacleCount = 2;
CircleObstacle[] circleObstacles;

LineDrawer[] lineDrawers;

class CircleObstacle {
  public float xPos,yPos;
  public float radius;
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
    int maxSteps = 5000;
    int stepCounter = 0;
    while (currentPosition.x >= fieldOffsetX && currentPosition.x <= width - fieldOffsetX && currentPosition.y >= fieldOffsetY && currentPosition.y <= height - fieldOffsetY && stepCounter < maxSteps) {
      linePoints.add(new LinePoint(currentPosition.x, currentPosition.y));

      PVector newPosition = rk4Step(currentPosition, integrationStep);

      currentPosition.x = newPosition.x;
      currentPosition.y = newPosition.y;

      stepCounter++;
    }
  }

  void display() {
    if (linePoints.size() < 2) {
      return;
    }

    float currentWeight = getTargetStrokeWeight(
      linePoints.get(0).position.x,
      linePoints.get(0).position.y
    );

    // draw lines for all created line points
    // float noiseScale = 0.01;
    for (int i = 0; i < linePoints.size(); i++) {
      LinePoint linePoint = linePoints.get(i);
      // linePoint.display();
      if (i > 0) {
        LinePoint linePoint1 = linePoints.get(i - 1);
        LinePoint linePoint2 = linePoint;
        float midX = (linePoint1.position.x + linePoint2.position.x) * 0.5;
        float midY = (linePoint1.position.y + linePoint2.position.y) * 0.5;
        float targetWeight = getTargetStrokeWeight(midX, midY);
        // int col = constrain(int(linePoint.position.x / scale), 0, cols - 1);
        // int row = constrain(int(linePoint.position.y / scale), 0, rows - 1);
        // float strokeWeightValue = map(/*noiseWeight * 1.2 * */noise(row * noiseScale + lineStrokeNoiseIteration * i * 0.1, col * noiseScale + lineStrokeNoiseIteration * i * 0.1)/*+ sineWaveWeight * 1.5 * sin(row * (noiseScale * 5))*/, 0, 1, lineStrokeWeightMin, lineStrokeWeightMax);
        // Smooth transitions between consecutive segments.
        float strokeWeightValue = lerp(
          currentWeight,
          targetWeight,
          strokeWeightSmoothing
        );
        stroke(0);
        strokeWeight(strokeWeightValue);
        line(linePoint1.position.x, linePoint1.position.y, linePoint2.position.x, linePoint2.position.y);
      }
    }
  }
}

void setup() {
  size(540, 960);

  fieldOffsetX = -float(width);
  fieldOffsetY = -float(height);
  
  rows = int(height * 3 / scale);
  cols = int(width * 3 / scale);
  visibleRows = int(height/scale);
  visibleCols = int(width/scale);

  densityCols = ceil(width / densityCellSize);
  densityRows = ceil(height / densityCellSize);
  lineDensity = new float[densityRows][densityCols];
  
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

  drawFlowField();
  drawCircleObstacles();
  // drawLineField();
  drawLines();

  noiseIteration += noiseIterationAmount;
  lineStrokeNoiseIteration += lineStrokeNoiseIterationAmount;
}

/** Generation Functions **/

void generateCircleObstacles() {
  float radiusMin = 100;
  float radiusMax = min(width / 4.0, height / 4.0) - 15;

  float positionalBuffer = 100;
  
  CircleObstacle firstCircle = new CircleObstacle();
  CircleObstacle secondCircle = new CircleObstacle();

  firstCircle.radius = random(radiusMin, radiusMax);
  firstCircle.xPos = random(positionalBuffer, width / 2 - positionalBuffer);
  firstCircle.yPos = random(positionalBuffer, height / 2 - positionalBuffer);
  
  secondCircle.radius = random(radiusMin, radiusMax);
  secondCircle.xPos = random(width / 2 + positionalBuffer, width - positionalBuffer);
  secondCircle.yPos = random(height / 2 + positionalBuffer, height - positionalBuffer);
  
  circleObstacles[0] = firstCircle;
  circleObstacles[1] = secondCircle;
  
  print("Circle 1 radius: ", firstCircle.radius, "\n");
  print("Circle 2 radius: ", secondCircle.radius, "\n");
}

void generateFlowField() {
  for (int i = 0; i < rows; i++) {
    for (int j = 0; j < cols; j++) {
      float worldX = fieldOffsetX + j * scale;
      float worldY = fieldOffsetY + i * scale;
      targetFlowField[i][j] = generateFlowFieldAngle(worldX, worldY);
      for (int c = 0; c < circleObstacleCount; c++) {
        targetFlowField[i][j] = calculateObstacleRepulsion(c, worldX, worldY, targetFlowField[i][j]);
      }
    }
  }

  for (int s = 0; s < smoothingIterationCount; s++) {
    // apply obstacle repulsion before each smoothing iteration
    // for (int i = 0; i < rows; i++) {
    //   for (int j = 0; j < cols; j++) {
    //     float worldX = fieldOffsetX + j * scale;
    //     float worldY = fieldOffsetY + i * scale;
    //     for (int c = 0; c < circleObstacleCount; c++) {
    //       targetFlowField[i][j] = calculateObstacleRepulsion(c, worldX, worldY, targetFlowField[i][j]);
    //     }
    //   }
    // }
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

  // apply obstacle repulsion after smoothing
  // for (int i = 0; i < rows; i++) {
  //   for (int j = 0; j < cols; j++) {
  //     float worldX = fieldOffsetX + j * scale;
  //     float worldY = fieldOffsetY + i * scale;
  //     for (int c = 0; c < circleObstacleCount; c++) {
  //       targetFlowField[i][j] = calculateObstacleRepulsion(c, worldX, worldY, targetFlowField[i][j]);
  //     }
  //   }
  // }
}

float generateFlowFieldAngle(float x, float y) {
  float sineWavelength = 540;
  float sine = sin(TWO_PI * y / sineWavelength);
  float flowFieldAngle = map(noiseWeight * noise(x * noiseScale + noiseIteration, y * noiseScale + noiseIteration) + sineWaveWeight * sine, 0, 1, 0, 2 * PI);
  return flowFieldAngle;
}

float calculateObstacleRepulsion(int circleIndex, float x, float y, float flowFieldAngle) {
  CircleObstacle circle = circleObstacles[circleIndex];
  float deltaX = x - circle.xPos;
  float deltaY = y - circle.yPos;
  float distance = sqrt(deltaX * deltaX + deltaY * deltaY);
  float influenceMultiplier = 4;
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
      // flowField[i][j] = targetFlowField[i][j];
    }
  }
}

void generateLineDrawers() {
  ArrayList<LineDrawer> drawers = new ArrayList<LineDrawer>();
  for (float x = fieldOffsetX + (lineSeedSpacing / 2); x < width - fieldOffsetX; x += lineSeedSpacing) {
    drawers.add(new LineDrawer("lid" + drawers.size(), x, -50));
    print("Creating line drawer " + drawers.size() + " at " + x + "\n");
  }
  lineDrawers = drawers.toArray(new LineDrawer[0]);
}

void buildLineDensity() {
  // Reset the density grid.
  for (int row = 0; row < densityRows; row++) {
    for (int col = 0; col < densityCols; col++) {
      lineDensity[row][col] = 0;
    }
  }

  // Each streamline contributes at most once per cell.
  for (LineDrawer drawer : lineDrawers) {

    // Track cells visited by this particular streamline.
    boolean[][] visited = new boolean[densityRows][densityCols];

    for (LinePoint point : drawer.linePoints) {
      float x = point.position.x;
      float y = point.position.y;

      // Ignore points outside the visible canvas.
      if (x < 0 || x >= width || y < 0 || y >= height) {
        continue;
      }

      int col = int(x / densityCellSize);
      int row = int(y / densityCellSize);

      if (!visited[row][col]) {
        lineDensity[row][col] += 1;
        visited[row][col] = true;
      }
    }
  }

  smoothLineDensity();
}

void smoothLineDensity() {
  float[][] smoothed = new float[densityRows][densityCols];

  for (int row = 0; row < densityRows; row++) {
    for (int col = 0; col < densityCols; col++) {
      float sum = 0;
      float weightSum = 0;

      // A 3x3 neighborhood with greater weight at the center.
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          int nr = row + dy;
          int nc = col + dx;

          if (nr < 0 || nr >= densityRows ||
              nc < 0 || nc >= densityCols) {
            continue;
          }

          float weight = (dx == 0 && dy == 0) ? 4.0 : 
                         (dx == 0 || dy == 0) ? 2.0 : 1.0;

          sum += lineDensity[nr][nc] * weight;
          weightSum += weight;
        }
      }

      smoothed[row][col] = sum / weightSum;
    }
  }

  lineDensity = smoothed;
}

/** Draw Functions **/

void drawFlowField() {
  int firstCol = max(
    0, int(ceil(-fieldOffsetX / scale))
  );
  int lastCol = min(
    cols - 1, int(floor((width - fieldOffsetX) / scale))
  );
  int firstRow = max(
    0, int(ceil(-fieldOffsetY / scale))
  );
  int lastRow = min(
    rows - 1, int(floor((height - fieldOffsetY) / scale))
  );

  for (int row = firstRow; row <= lastRow; row++) {
    for (int col = firstCol; col <= lastCol; col++) {
      // row index is technically y value and col index is technically x value
      float worldX = fieldOffsetX + col * scale;
      float worldY = fieldOffsetY + row * scale;

      pushMatrix();
      translate(worldX, worldY);
      rotate(flowField[row][col]);
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
    fill(255, 0, 0, 127);
    circle(
      circleObstacles[i].xPos,
      circleObstacles[i].yPos,
      circleObstacles[i].radius * 2
    );
  }
}

void drawLineField() {
  float seedSpacing = scale;

  // Seed lines across the visible top edge.
  for (float startX = seedSpacing / 2;
       startX < width;
       startX += seedSpacing) {

    PVector currentPosition = new PVector(startX, 0);

    int maxSteps = 5000;

    for (int step = 0; step < maxSteps; step++) {

      // Stop when the streamline leaves the visible canvas.
      if (
        currentPosition.x < 0 ||
        currentPosition.x >= width ||
        currentPosition.y < 0 ||
        currentPosition.y >= height
      ) {
        break;
      }

      PVector nextPosition = rk4Step(
        currentPosition,
        scale
      );

      // Draw only segments that remain inside the canvas.
      if (
        nextPosition.x >= 0 &&
        nextPosition.x < width &&
        nextPosition.y >= 0 &&
        nextPosition.y < height
      ) {
        strokeWeight(1);
        stroke(0, 0, 255);

        line(
          currentPosition.x,
          currentPosition.y,
          nextPosition.x,
          nextPosition.y
        );
      }

      currentPosition = nextPosition;
    }
  }
}

void drawLines() {
  for (int i = 0; i < lineDrawers.length; i++) {
    lineDrawers[i].update();
  }

  buildLineDensity();

  for (int i = 0; i < lineDrawers.length; i++) {
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
  // convert screen coordinates to field-grid coordinates
  float gx = (x - fieldOffsetX) / scale;
  float gy = (y - fieldOffsetY) / scale;

  // clamp to valid grid domain
  gx = constrain(gx, 0, cols - 1);
  gy = constrain(gy, 0, rows - 1);

  int x0 = int(floor(gx));
  int y0 = int(floor(gy));

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

  float magnitudeSq = vx * vx + vy * vy;

  // Handle opposing directions whose average nearly cancels.
  if (magnitudeSq < 0.000001) {
    return new PVector(cos(a00), sin(a00));
  }

  float invMagnitude = 1.0 / sqrt(magnitudeSq);

  return new PVector(
    vx * invMagnitude,
    vy * invMagnitude
  );
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

float getTargetStrokeWeight(float x, float y) {
  int col = constrain(
    int(x / densityCellSize),
    0,
    densityCols - 1
  );

  int row = constrain(
    int(y / densityCellSize),
    0,
    densityRows - 1
  );

  // Density: high density produces thin lines.
  float density = lineDensity[row][col];

  // Tune this to match your actual density values.
  float densityNormalized = constrain(
    density / 4,
    0,
    1
  );

  densityNormalized = pow(densityNormalized, 0.8);

  float densityWeight = lerp(
    lineStrokeWeightMax,
    lineStrokeWeightMin,
    densityNormalized
  );

  // Noise adds a subtle variation around the density weight.
  float n = noise(
    x * lineStrokeNoiseIteration + noiseIteration * lineStrokeNoiseIterationAmount,
    y * lineStrokeNoiseIteration + noiseIteration * lineStrokeNoiseIterationAmount
  );

  float noiseOffset = map(n, 0, 1, -1, 1);

  float noiseAmount = 0.2 * (
    lineStrokeWeightMax - lineStrokeWeightMin
  );

  return constrain(
    densityWeight + noiseOffset * noiseAmount,
    lineStrokeWeightMin,
    lineStrokeWeightMax
  );
}
