// Theo Walker
// Max Planck Florida Institute
// naroom@gmail.com

package cellMagicWand;

public class CartesianPixel {

	public int x;
	public int y; 
	public double r; 
	public double theta; 
	
	public CartesianPixel(double r, double theta, int cx, int cy, int maxX, int maxY){
		this.r = r;
		this.theta = theta;
		polarToCartesian(cx,cy); //populate x and y fields 

		if(this.x < 0){
			this.x = 0;			
		}
		else if(this.x > maxX){
			this.x = maxX;
		}
		if(this.y < 0){
			this.y = 0;			
		}
		else if(this.y > maxY){
			this.y = maxY;
		}
	}

	public CartesianPixel(CartesianPixel a, CartesianPixel c, int cx, int cy, int maxX, int maxY){
		//makes a new CartesianPixel between a and c
		this.r = (a.r + c.r)/2;
		this.theta = meanAngle(a.theta, c.theta);
		polarToCartesian(cx,cy); //populate x and y fields
		
		//Handle edge case where the edge goes directly diagonally across two pixels
		//Odds are something like one in a million, but it does happen.
		if(Math.abs(a.x-c.x) == 1 && Math.abs(a.y-c.y) == 1 && Math.abs(a.theta-c.theta) < Constants.EPSILON && Math.abs(a.r-c.r) < Constants.EPSILON){
			if(theta < Math.PI/2){
				this.x = a.x - 1;
				this.y = a.y;
			}
			else if(theta < Math.PI){
				this.x = a.x;
				this.y = a.y - 1;
			}
			else if(theta < Math.PI * 3/2){
				this.x = a.x + 1;
				this.y = a.y;
			}
			else {
				this.x = a.x;
				this.y = a.y + 1;
			}
		}
		
		//shove points inside image if they're outside the image bounds
		if(this.x < 0){
			this.x = 0;			
		}
		else if(this.x > maxX){
			this.x = maxX;
		}
		if(this.y < 0){
			this.y = 0;			
		}
		else if(this.y > maxY){
			this.y = maxY;
		}
	}
	
	private void polarToCartesian(int cx, int cy){
		double r = this.r;
		double theta = this.theta;

		/* OK this is the one you use with ImageJ ROIs, definitely
		//x
		double cosTheta = Math.cos(theta);
		if(cosTheta < 0)
			this.x = (int) Math.ceil(r*cosTheta) + cx;
		else
			this.x = (int) Math.floor(r*cosTheta) + cx;
			
		//y
		double sinTheta = Math.sin(theta);
		if(sinTheta < 0)
			this.y = (int) Math.ceil(r*sinTheta) + cy;
		else
			this.y = (int) Math.floor(r*sinTheta) + cy;
		 */		

		//this is for command line ROIs
		r=r-1.5;
		//x
		double cosTheta = Math.cos(theta);
		if(cosTheta < 0)
			this.x = (int) Math.ceil(r*cosTheta) + cx;
		else
			this.x = (int) Math.ceil(r*cosTheta) + cx;
			
		//y
		double sinTheta = Math.sin(theta);
		if(sinTheta < 0)
			this.y = (int) Math.ceil(r*sinTheta) + cy;
		else
			this.y = (int) Math.ceil(r*sinTheta) + cy;
		
	}
	
	private double meanAngle(double thetaA, double thetaB){
		//takes the average of two angles (radians).
		//You can't do it just by adding the two angles and dividing by 2; 
		//consider what the average of 10 and 350 would be in that case.
		double biggerAngle, smallerAngle;
		if(thetaA > thetaB){
			biggerAngle = thetaA;
			smallerAngle = thetaB;
		}
		else{
			biggerAngle = thetaA;
			smallerAngle = thetaB;				
		}
		double angleDifference = biggerAngle - smallerAngle;
		double twoPi = Math.PI*2;
		if(angleDifference > Math.PI){
			biggerAngle = biggerAngle - twoPi;
		}
		return (biggerAngle + smallerAngle)/2 % twoPi;
	}
	
}
