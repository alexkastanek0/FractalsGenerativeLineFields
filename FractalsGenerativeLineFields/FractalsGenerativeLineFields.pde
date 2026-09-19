class CircleObstacle {
  public int xPos,yPos;
  public int radius;
}

float scale = 10;
int rows,cols;
float[][] flowField;
float noiseIterationAmount = 0.001;
float noiseIteration = 0;

int circleObstacleCount = 2;
CircleObstacle[] circleObstacles;

void setup() {
  size(360, 640);
  
  rows = int(height/scale);
  cols = int(width/scale);
  
  circleObstacles = new CircleObstacle[circleObstacleCount];
  generateCircleObstacles();
  
  flowField = new float[rows][cols];
  generateFlowField();
}

void draw() {
  background(255);
  generateFlowField();
  drawFlowField();
  drawCircleObstacles();
  drawLineField();
  noiseIteration += noiseIterationAmount;
}

void generateFlowField() {
  for (int i = 0; i < rows; i++) {
    for (int j = 0; j < cols; j++) {
      flowField[i][j] = generateFlowFieldAngle(i, j);
    }
  }
}

float generateFlowFieldAngle(float row, float col) {
  float noiseScale = 0.01;
  float noiseWeight = 0.4;
  float sineWaveWeight = 0.15;
  float flowFieldAngle = map(noiseWeight * noise(row * noiseScale + noiseIteration, col * noiseScale + noiseIteration) + sineWaveWeight * sin(row * (noiseScale * 5)), 0, 1, 0, 2 * PI);
  // calculate repulsion
  for (int c = 0; c < circleObstacleCount; c++) {
    CircleObstacle circle = circleObstacles[c];
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

      // blend the angles
      flowFieldAngle = lerpAngle(
        flowFieldAngle,
        tangentAngle,
        strength
      );
    }
  }
  return flowFieldAngle;
}

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

void generateCircleObstacles() {
  CircleObstacle firstCircle = new CircleObstacle();
  CircleObstacle secondCircle = new CircleObstacle();
  int radiusBuffer = 7;
  int positionalBuffer = 10;
  
  firstCircle.radius = int(random(radiusBuffer, cols / 2 - radiusBuffer)) + 1;
  firstCircle.xPos = int(random(0 + firstCircle.radius, cols / 2 - firstCircle.radius));
  firstCircle.yPos = int(random(positionalBuffer + firstCircle.radius, rows / 2 - firstCircle.radius));
  
  secondCircle.radius = int(random(radiusBuffer, cols / 2 - radiusBuffer)) + 1;
  secondCircle.xPos = int(random(cols / 2 + firstCircle.radius, cols - firstCircle.radius));
  secondCircle.yPos = int(random(rows / 2 + firstCircle.radius, rows - firstCircle.radius - positionalBuffer));
  
  circleObstacles[0] = firstCircle;
  circleObstacles[1] = secondCircle;
  
  print("Circle 1 radius: ", firstCircle.radius, "\n");
  print("Circle 2 radius: ", secondCircle.radius, "\n");
}

void drawFlowField() {
  for (int i = 0; i < rows; i++) {
    for (int j = 0; j < cols; j++) {
      pushMatrix();
      translate(j*scale, i*scale); // row index is technically y value and col index is technically x value
      rotate(flowField[i][j]);
      line(0, 0, scale*0.5, 0);
      popMatrix();
    }
  }
}

void drawCircleObstacles() {
  for (int i = 0; i < circleObstacleCount; i++) {
    circle(circleObstacles[i].xPos * scale, circleObstacles[i].yPos * scale, circleObstacles[i].radius * scale);
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
      line(x, y, newX, newY);
      x = newX;
      y = newY;
    }
  }
}
