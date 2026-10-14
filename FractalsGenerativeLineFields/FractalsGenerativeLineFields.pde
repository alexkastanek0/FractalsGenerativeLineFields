import com.hamoid.*;

float scale = 10;
int rows,cols;
int visibleRows, visibleCols;

float[][] flowField;
float fieldOffsetX;
float fieldOffsetY;

float[][] smoothedFlowField;
int smoothingIterationCount = 50;

float[][] targetFlowField;
float noiseIteration = 0;
float noiseIterationAmountSlow = 0.0001;
float fieldMorphSpeedSlow = 0.001;
float noiseIterationAmountFast = 0.1;
float fieldMorphSpeedFast = 0.5;
float noiseIterationAmount = 0;
float fieldMorphSpeed = 0;
boolean useFastSpeed = true;


float noiseScale = 0.01;
float noiseWeight = 0.4;
float sineWaveWeight = 0.15;
float lineSeedSpacing = 20;

float densityCellSize = 30;
int densityCols, densityRows;
float[][] lineDensity;
float noiseInfluence = 0.025;
float lineStrokeNoiseIterationAmount = 0.015;
float lineStrokeNoiseIteration = 0.02;
float lineStrokeWeightMin = 1;
float lineStrokeWeightMax = 50;
float strokeWeightSmoothing = 1;

int circleObstacleCount = 2;
CircleObstacle[] circleObstacles;

LineDrawer[] lineDrawers;
PGraphics lineBuffer;
int renderScale = 3;

int framerate = 60;
boolean isRecording = false;

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
    int n = linePoints.size();
    if (n < 3) return;
  
    // --------------------------------------------------
    // 1. Sample target width at each segment midpoint.
    // --------------------------------------------------
    float[] targetWidths = new float[n];
  
    for (int i = 0; i < n; i++) {
      PVector p = linePoints.get(i).position;
  
      targetWidths[i] = getTargetStrokeWeight(p.x, p.y);
    }
  
    // --------------------------------------------------
    // 2. Smooth the width profile.
    // --------------------------------------------------
    // Two passes of a small Gaussian filter reduce abrupt
    // transitions without making every line uniform.
    float[] widths = targetWidths.clone();
  
    int radius = 8;
    float sigma = 3.5;
  
    for (int pass = 0; pass < 2; pass++) {
      float[] filtered = new float[n];
  
      for (int i = 0; i < n; i++) {
        float sum = 0;
        float total = 0;
  
        for (int j = -radius; j <= radius; j++) {
          int k = constrain(i + j, 0, n - 1);
  
          float g = exp(-(j * j) / (2.0 * sigma * sigma));
  
          sum += widths[k] * g;
          total += g;
        }
  
        filtered[i] = sum / total;
      }
  
      widths = filtered;
    }
  
    // --------------------------------------------------
    // 3. Limit width changes along the path.
    // --------------------------------------------------
    // Widths are in screen pixels. Since integrationStep
    // is 1, this limits changes per approximately 1 pixel
    // of streamline distance.
    float maxWidthChangePerPixel = 0.12;
  
    // Forward pass.
    for (int i = 1; i < n; i++) {
      PVector a = linePoints.get(i - 1).position;
      PVector b = linePoints.get(i).position;
  
      float distance = PVector.dist(a, b);
      float limit = maxWidthChangePerPixel * distance;
  
      widths[i] = constrain(
        widths[i],
        widths[i - 1] - limit,
        widths[i - 1] + limit
      );
    }
  
    // Backward pass.
    for (int i = n - 2; i >= 0; i--) {
      PVector a = linePoints.get(i).position;
      PVector b = linePoints.get(i + 1).position;
  
      float distance = PVector.dist(a, b);
      float limit = maxWidthChangePerPixel * distance;
  
      widths[i] = constrain(
        widths[i],
        widths[i + 1] - limit,
        widths[i + 1] + limit
      );
    }
  
    // --------------------------------------------------
    // 4. Calculate unit tangents at every point.
    // --------------------------------------------------
    PVector[] tangents = new PVector[n];
  
    for (int i = 0; i < n; i++) {
      PVector tangent;
  
      if (i == 0) {
        tangent = PVector.sub(
          linePoints.get(1).position,
          linePoints.get(0).position
        );
      } else if (i == n - 1) {
        tangent = PVector.sub(
          linePoints.get(n - 1).position,
          linePoints.get(n - 2).position
        );
      } else {
        PVector incoming = PVector.sub(
          linePoints.get(i).position,
          linePoints.get(i - 1).position
        );
  
        PVector outgoing = PVector.sub(
          linePoints.get(i + 1).position,
          linePoints.get(i).position
        );
  
        incoming.normalize();
        outgoing.normalize();
  
        tangent = PVector.add(incoming, outgoing);
  
        // A 180-degree reversal has no well-defined
        // averaged tangent. Fall back to outgoing.
        if (tangent.magSq() < 0.000001) {
          tangent = outgoing.copy();
        }
      }
  
      if (tangent.magSq() < 0.000001) {
        tangent = new PVector(1, 0);
      } else {
        tangent.normalize();
      }
  
      tangents[i] = tangent;
    }
  
    // --------------------------------------------------
    // 5. Construct curvature-aware ribbon boundaries.
    // --------------------------------------------------
    PVector[] left = new PVector[n];
    PVector[] right = new PVector[n];
  
    // Maximum miter length relative to half-width.
    // Lower values reduce protrusions at tight bends.
    float miterLimit = 1.5;
  
    for (int i = 0; i < n; i++) {
      PVector p = linePoints.get(i).position;
      float halfWidth = widths[i] * 0.5;
  
      PVector normal;
  
      if (i == 0) {
        PVector t = tangents[i];
        normal = new PVector(-t.y, t.x);
  
      } else if (i == n - 1) {
        PVector t = tangents[i];
        normal = new PVector(-t.y, t.x);
  
      } else {
        PVector prev = linePoints.get(i - 1).position;
        PVector next = linePoints.get(i + 1).position;
  
        PVector incoming = PVector.sub(p, prev);
        PVector outgoing = PVector.sub(next, p);
  
        if (incoming.magSq() > 0.000001) {
          incoming.normalize();
        }
  
        if (outgoing.magSq() > 0.000001) {
          outgoing.normalize();
        }
  
        PVector n1 = new PVector(-incoming.y, incoming.x);
        PVector n2 = new PVector(-outgoing.y, outgoing.x);
  
        normal = PVector.add(n1, n2);
  
        if (normal.magSq() < 0.000001) {
          normal = n2.copy();
        } else {
          normal.normalize();
        }
  
        // Correct for the angle between the averaged
        // normal and the incoming segment normal.
        float denominator = normal.dot(n1);
        float miterLength = halfWidth;
  
        if (denominator > 0.0001) {
          miterLength = halfWidth / denominator;
        }
  
        // Cap the offset at sharp turns.
        miterLength = min(
          miterLength,
          halfWidth * miterLimit
        );
  
        // Store the capped offset in the normal vector.
        normal.mult(miterLength / max(halfWidth, 0.0001));
      }
  
      left[i] = new PVector(
        p.x + normal.x * halfWidth,
        p.y + normal.y * halfWidth
      );
  
      right[i] = new PVector(
        p.x - normal.x * halfWidth,
        p.y - normal.y * halfWidth
      );
    }
  
    // --------------------------------------------------
    // 6. Draw one solid black polygon at high resolution.
    // --------------------------------------------------
    lineBuffer.beginDraw();
    lineBuffer.noStroke();
    lineBuffer.fill(0);
  
    lineBuffer.beginShape();
  
    for (int i = 0; i < n; i++) {
      lineBuffer.vertex(
        left[i].x * renderScale,
        left[i].y * renderScale
      );
    }
  
    for (int i = n - 1; i >= 0; i--) {
      lineBuffer.vertex(
        right[i].x * renderScale,
        right[i].y * renderScale
      );
    }
  
    lineBuffer.endShape(CLOSE);
    lineBuffer.endDraw();
  
    image(lineBuffer, 0, 0, width, height);
  }
}

void setup() {
  size(540, 960);
  
  lineBuffer = createGraphics(
    width * renderScale,
    height * renderScale
  );
  smooth(8);
  
  frameRate(framerate);
  noiseIterationAmount = noiseIterationAmountFast;
  fieldMorphSpeed = fieldMorphSpeedFast;

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

  drawLines();
  // drawFlowField();
  // drawCircleObstacles();
  // drawLineField();
  
  if (isRecording) {
    saveFrame("render/frame-####.png");
  }

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
  lineBuffer.beginDraw();
  lineBuffer.background(255);
  lineBuffer.endDraw();
  
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

  float noiseAmount = noiseInfluence * (
    lineStrokeWeightMax - lineStrokeWeightMin
  );

  return constrain(
    densityWeight + noiseOffset * noiseAmount,
    lineStrokeWeightMin,
    lineStrokeWeightMax
  );
}

void keyPressed() {
  if (key == 'r' && !isRecording) {
    isRecording = true;
    println("Recording started...");
  }
  if (key == 'q' && isRecording) {
    isRecording = false;
    println("Recording stopped. Video saved.");
    exit();
  }
  if (key == ' ') {
    if (useFastSpeed == true) {
      useFastSpeed = false;
      noiseIterationAmount = noiseIterationAmountSlow;
      fieldMorphSpeed = fieldMorphSpeedSlow;
    } else {
      useFastSpeed = true;
      noiseIterationAmount = noiseIterationAmountFast;
      fieldMorphSpeed = fieldMorphSpeedFast;
    }
  }
}
