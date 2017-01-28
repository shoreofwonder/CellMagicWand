% The "online" form of findGCaMP
% Process is:
% (1) Get an image
% (2) Subtract the previous image to get a derivative image
% (3) Correct intensity differences from scope
% (4) Find the image gradient (Prewitt edge detector)
% (5) Run the Hough transform on the gradient (Peng 2007)
% (6) Combine nearby peaks using a small Gaussian filter
% Then, for each peak in the Hough:
% (7) Polar transform and trace cell edge (Nandy 2007)
% (8) Keep or exclude cell based on edge score (mean/std)
% (9) Combine cell with any other copies of itself (radius based, DBSCAN)


% ========================================== %
% Read in source data

% Read the time series you want to segment into the 'tifs' variable.
% if your data's all in one multipage tif, use readMultiTif(tifFile)
% if it's a set of individual tifs in a dir, use readTifs(tifDir)
disp('reading in images');
% tifs = readMultiTif('I:\shrewData\1319\Registered t000016-001.tif');
tifs = readTifs('I:\ferretData\1344\t04-filter-reg');
% tifs = readTifs('I:\findGCaMP\training-datasets\ts1329-t06-reg-1-200');

% ========================================== %
% Parameters you should play with

% Look at your cells in ImageJ and draw a little box around the smallest
% cell and another around the largest cell. Put the size numbers in here.
% Typical ranges: 6 to 14, or 12 to 18.
cellDiameterMin = 6; 
cellDiameterMax = 14;

% The Hough cutoff is the core 'selectivity vs sensitivity' number.
% Decrease it for more sensitivity, raise it for more selectivity.
% I'm working on a way to determine this theoretically, or at least
% make it more intuitive. 
% But for now you'll have to calibrate it manually (sorry).
% One way to get at this number quickly is to run the program once with it
% at a high cutoff (say, 60000) and look at the accumMax.png output image. 
% Find the lowest peak accumMax that corresponds to a cell, and put the 
% value in here.
houghCutoff = 25000;

% ========================================== %
% Parameters you can probably leave alone

% The gradient threshold determines what will be considered as a possible
% cell. All this does is eliminate parts of the gradient that are clearly 
% noise  so we don't spend any processor time looking at them. You probably
% won't need to change this.
imageBitDepth = 13;
imageMaxValue = 2^(imageBitDepth)-1; 
gradientThreshold = imageMaxValue/10;

% The expected distance between two cells.
% If the algorithm appears to be excluding ROIs that are near each other,
% make this lower.
% If it is drawing many ROIs very close together, make this higher.
% Usually cellDiameterMax / 2 works well.
minDistBetweenCells = cellDiameterMax / 2; 

% The sigma determining the Gaussian function
% If you start to get multiple peaks in a single cell, increase this.
gaussianSigma = 1.2;
gaussianSize = 7; % How large the box containing the Gaussian filter is

% The required score for something to be a cell. 2 is a good value.
% Score is the mean of the edge intensity divided by the standard deviation.
% So an edge needs to be (1) strong and (2) consistent in intensity 
% as it travels around the cell. Lower this if you have a lot of half-cells
% or to push up sensitivity.
scoreThresh = 2.0;

% Require a cell to show up at least this many times for it to be detected.
% If you want to find every cell possible (most sensitive), set this to 1.
minRequiredEvents = 1;

% ========================================== %
% End input parameters -- code starts here

rMin = cellDiameterMin / 2;
rMax = cellDiameterMax / 2;
radrange = [rMin,rMax];
numRadii = length(rMin+0.5:rMax); % might be useful for auto-calculation of Hough cutoff?


% ========================================== %
% Find derivative images
disp('Calculating time derivative images');
zEdgeFilter = zeros(3,3,3);

derivTifs = tifs(:,:,2:end) - tifs(:,:,1:end-1);
clear tifs;

writeTifs(derivTifs,'I:/findGCaMP/derivTifs/');
derivMax = max(derivTifs,[],3);
writeDoubleTif(derivMax,'derivMax.tif');

[height width nFrames] = size(derivTifs);

% ========================================== %
% Correct for the intensity fall-off over the image.

% A rough measurement showed that there is a linear fall-off in intensity
% as you get further from the center. The corners are at about 1/3
% intensity and the middle of the edge of the image is at about 2/3
% intensity. So we apply the mask to equalize this. 
% (A more accurate measurement should happen sometime, of course!)
intensityCorrectionMask = ones(height,width);
centerY = height/2;
centerX = width/2;
for i=1:height
    for j=1:width
        distToCenter = sqrt((i-centerY)^2+(j-centerX)^2);
        intensityCorrectionMask(i,j) = (1+3*distToCenter/width)*intensityCorrectionMask(i,j);
    end
end

derivTifs = uint16(bsxfun(@times,double(derivTifs),intensityCorrectionMask));

% ========================================== %
% Find the image gradient (Prewitt edge detector)
grdMagTifs = zeros(size(derivTifs));
accumTifs = zeros(size(derivTifs));
cellOutlines = zeros(size(derivTifs));

s=1; %index
numDrawn = 0;
clear seeds;
accumulatedCellOutlines = zeros(size(derivTifs));
for t=1:nFrames
    if mod(t,10)==9
        disp([num2str(100*t/nFrames) '% completed.']);
    end
    % get FFT frame
    frame = double(derivTifs(:,:,t));
    
    % Prewitt filter to get gradients
    prewittX = [
        1 0 -1
        1 0 -1
        1 0 -1];
    prewittY = [
        1 1 1
        0 0 0
        -1 -1 -1];

    gradientX = conv2(frame, prewittX, 'valid');
    gradientY = conv2(frame, prewittY, 'valid');

    gradientX = addBorder(gradientX,0); %pad to original image size
    gradientY = addBorder(gradientY,0); %pad to original image size

    gradientMag = sqrt(gradientX.^2 + gradientY.^2);
    grdMagTifs(:,:,t) = gradientMag;
    
    % ========================================== %
    % Hough transform to find circles
    accum = CircularHough_Grd(gradientX, gradientY, radrange, gradientThreshold);

    % ========================================== %
    % Combine nearby peaks using a small Gaussian filter
    f = fspecial('gaussian',gaussianSize,gaussianSigma);
    accum = imfilter(accum,f);
    accumTifs(:,:,t) = accum;
    
    % the centroids of each blob will be our seeds
    accumThresh = accum > houghCutoff; % this is OK for now; think about it later
    CC = bwconncomp(accumThresh);
    STATS = regionprops(CC,'Centroid');
    centroidImg = zeros(size(accumThresh));
    
    if isempty(STATS)
        continue;
    end
    
    % ========================================== %
    % Polar transform and trace cell edge (Nandy 2007)
    cellOutline = zeros(size(frame));
    foundCell = false;
    for i=1:length(STATS)
        seed.edgeSeedPoint = [round(STATS(i).Centroid(2)),round(STATS(i).Centroid(1))];
        seedStats = gcampSeedStats(seed, frame, cellDiameterMin, cellDiameterMax);

        if seedStats.removed==1
            % bad ROI; couldn't fit a circular edge to it. 
            continue;
        end
        if seedStats.score < scoreThresh
            % We managed to fit a circular edge, but it was a crappy one.
            continue;
        end
        
        % Take the polar image at each seed point
        seeds{s}.edgeSeedPoint = [round(STATS(i).Centroid(2)),round(STATS(i).Centroid(1))];
        seeds{s}.outlineX = seedStats.outlineX;
        seeds{s}.outlineY = seedStats.outlineY;
        seeds{s}.enclosedX = seedStats.enclosedX;
        seeds{s}.enclosedY = seedStats.enclosedY;
        seeds{s}.score = seedStats.score;
        seeds{s}.t = t;
         
        %draw cellOutline image for cells with a good score
        X=seeds{s}.outlineX;
        Y=seeds{s}.outlineY;
        for j=1:length(X)
            x=Y(j);
            y=X(j);
            cellOutline(x,y) = 1;
        end
        numDrawn = numDrawn+1;
        
        s=s+1;
        foundCell = true;
    end
    if foundCell
        disp(['  ' num2str(length(seeds)) ' cell events found.']);
    end
    cellOutlines(:,:,t) = cellOutline;
end

% write some output data
imwrite(uint16(max(grdMagTifs,[],3)),'grdMagMax.tif','tif');
imwrite(uint16(max(accumTifs,[],3)),'accumMax.tif','tif');

% clean up excess data; we only made these for debugging and performance
% tuning, so they can be removed from the final version entirely.
clear grdMagTifs;
clear accumTifs;
clear cellOutlines;


% ========================================== %
% Combine cell with any other copies of itself (radius based, DBSCAN)
disp('combining frame ROIs to cells');
% Use DBSCAN to find unique cells.
points = zeros(length(seeds),2);
for s=1:length(seeds)
    points(s,:) = seeds{s}.edgeSeedPoint;
end

% run dbscan
clusterLabels = dbscan(points,minRequiredEvents-1,minDistBetweenCells);

clear cells;
%set up the cells data structure
for c=1:max(clusterLabels)
    cells{c}.clusterSize = length(find(clusterLabels == c));
    cells{c}.maxScore = 0;
end

% assign each cell the outline that had the best score
for s=1:length(seeds)
    c = clusterLabels(s);
    if c <= 0
        continue;
    end
    if seeds{s}.score > cells{c}.maxScore
        cells{c}.maxScore = seeds{s}.score;
        cells{c}.outlineX = seeds{s}.outlineX;
        cells{c}.outlineY = seeds{s}.outlineY;
        cells{c}.enclosedX = seeds{s}.enclosedX;
        cells{c}.enclosedY = seeds{s}.enclosedY;
        cells{c}.t = seeds{s}.t;
    end
end

% write out the cells into a cellOutlines image
cellOutline = zeros(height,width);
for c=1:length(cells)
    X=cells{c}.outlineX;
    Y=cells{c}.outlineY;
    for j=1:length(X)
        x=Y(j);
        y=X(j);
        cellOutline(x,y) = 1;
    end
end
writeDoubleTif(cellOutline,'cellOutline.tif');

disp('done');