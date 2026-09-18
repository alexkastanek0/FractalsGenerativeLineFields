float scale = 10;
int rows,cols;
float[][] flowField;

void setup() {
  size(360, 640);
  background(255);
  rows = int(height/scale);
  cols = int(width/scale);
  flowField = new float[rows][cols];
  generateFlowField();
}

void draw() {
  drawFlowField();
}

void generateFlowField() {
  for (int i = 0; i < rows; i++) {
    for (int j = 0; j < cols; j++) {
      // flow field generation generation begins with line pointing down by default
      flowField[i][j] = PI/2;
    }
  }
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
