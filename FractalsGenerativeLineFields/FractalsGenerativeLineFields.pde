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
}

void generateFlowField() {
  float noiseScale = 0.01;
  float sineWaveWeight = 0.5;
  for (int i = 0; i < rows; i++) {
    for (int j = 0; j < cols; j++) {
      // flow field generation generation begins with line pointing down by default
      flowField[i][j] = map(noise(i * noiseScale, j * noiseScale) + sineWaveWeight * sin(i * (noiseScale * 5)), 0, 1, 0, 2 * PI);
    }
  }
}

void generateCircleObstacles() {
  CircleObstacle firstCircle = new CircleObstacle();
  CircleObstacle secondCircle = new CircleObstacle();
  int radiusBuffer = 2;
  
  firstCircle.radius = int(random(0, cols / 2 - radiusBuffer)) + 1;
  firstCircle.xPos = int(random(0 + firstCircle.radius, cols / 2 - firstCircle.radius)) + 1;
  firstCircle.yPos = int(random(0 + firstCircle.radius, rows / 2 - firstCircle.radius)) + 1;
  
  secondCircle.radius = int(random(0, cols / 2 - radiusBuffer)) + 1;
  secondCircle.xPos = int(random(cols / 2 + firstCircle.radius, cols - firstCircle.radius)) + 1;
  secondCircle.yPos = int(random(rows / 2 + firstCircle.radius, rows - firstCircle.radius)) + 1;
  
  circleObstacles[0] = firstCircle;
  circleObstacles[1] = secondCircle;
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
