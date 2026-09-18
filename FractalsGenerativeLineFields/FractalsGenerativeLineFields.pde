class CircleObstacle {
  public int xPos,yPos;
  public int radius;
}

float scale = 10;
int rows,cols;
float[][] flowField;

int circleObstacleCount = 2;
CircleObstacle[] circleObstacles;

void setup() {
  size(360, 640);
  background(255);
  
  rows = int(height/scale);
  cols = int(width/scale);
  flowField = new float[rows][cols];
  generateFlowField();
  
  circleObstacles = new CircleObstacle[circleObstacleCount];
  generateCircleObstacles();
}

void draw() {
  drawFlowField();
  drawCircleObstacles();
  drawLineField();
}

void generateFlowField() {
  float noiseScale = 0.01;
  float noiseWeight = 0.4;
  float sineWaveWeight = 0.15;
  for (int i = 0; i < rows; i++) {
    for (int j = 0; j < cols; j++) {
      flowField[i][j] = map(noiseWeight * noise(i * noiseScale, j * noiseScale) + sineWaveWeight * sin(i * (noiseScale * 5)), 0, 1, 0, 2 * PI);
    }
  }
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
      for (int c = 0; c < circleObstacleCount; c++) {
        PVector repulsiveForce = calculateObstacleRepulsion(x, y, circleObstacles[c]);
        newX += repulsiveForce.x * 10;
        newY += repulsiveForce.y * 10;
      }
      line(x, y, newX, newY);
      x = newX;
      y = newY;
    }
  }
}

PVector calculateObstacleRepulsion(float x, float y, CircleObstacle circle) {
  float deltaX = x - circle.xPos * scale;
  float deltaY = y - circle.yPos * scale;
  float distance = sqrt(deltaX * deltaX + deltaY * deltaY);
  float influenceMultiplier = 1.5;
  float influence = circle.radius * scale * influenceMultiplier;
  
  if (distance > influence) {
    return new PVector(0, 0);
  }
  
  float strength = 1 - distance / influence;
  
  return new PVector(deltaX / distance * strength, deltaY / distance * strength);
}
