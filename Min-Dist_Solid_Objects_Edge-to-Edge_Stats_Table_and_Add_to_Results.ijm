/*	ImageJ Macro to calculate minimum distances between the edges of solid objects in a two-image set.
	One image contains the "inner" object and one the "outer" enclosing object.
	This allows you to analyze objects with broken rings.
 	Inwards or Outwards directions using "In-Line" (ImageJ "Outlines" are inside of binary objects").
	6/7/2016 Peter J. Lee (NHMFL), simplified 6/13-28/2016, changed table output extension to csv for Excel 2016 compatibility 8/15/2017
	8/18/2017 Removed a label function that was not working beyond 255 object noticed by Ian Pong and Luc LaLonde at LBNL
	9/9/2017 Added garbage clean up as suggested by Luc LaLonde at LBNL.
	v180906 Removed redundant dialog line.
	v180907 Updated ASC functions to latest versions. Added checks for outlier areas and isolated pixels.
	v180910 Very minor code cleanup.
	v180911-v180912 Major reworking to leverage use of new Table functions resulting in a 93%  reduction in run time.
	v180913 Added option to output coordinates and distances in table suitable for the line color coder macro.
	v180924-5 Added option to analyze both directions. Added a few minor tweaks. Added a variety of memory flushes but with little impact
	v180928 Removed some redundant code.
	v180928b Only ROIs are duplicated for pixel acquisition. v190325 minor tweaks to syntax.
	v211029 Updated functions
*/
	requires("1.52a"); /* This version uses Table functions, added in ImageJ 1.52a */
	macroL = "Min-Dist_Solid_Objects_Edge-to-Edge_Stats_Table_and_Add_to_Results_v211029.ijm";
	run("Collect Garbage");
	saveSettings(); /* To restore settings at the end */
	snapshot();
		
	/*   ('.')  ('.')   Black objects on white background settings   ('.')   ('.')   */	
	/* Set options for black objects on white background as this works better for publications */
	run("Options...", "iterations=1 white count=1"); /* Set the background to white */
	run("Colors...", "foreground=black background=white selection=yellow"); /* Set the preferred colors for these macros */
	setOption("BlackBackground", false);
	run("Appearance...", " "); if(is("Inverting LUT")) run("Invert LUT"); /* do not use Inverting LUT */
	/*	The above should be the defaults but this makes sure (black particles on a white background)
		http://imagejdocu.tudor.lu/doku.php?id=faq:technical:how_do_i_set_up_imagej_to_deal_with_white_particles_on_a_black_background_by_default */
	cleanUp(); /* function to cleanup old windows (I hope you did not want them). Run before cleanup.*/
	/* ROI manager check must be after inner/outer check */
	maxMemFactor = 100000000/IJ.maxMemory();
	mem = IJ.currentMemory();
	mem /=1000000;
	startMemPC = mem*maxMemFactor;
	titleActiveImage = getTitle();
	dirActiveImage = getDirectory("image");
	activeImageIs = "neither";
	if((indexOf(titleActiveImage, "nner"))>= 0) {
		activeImageIs = "inner";
	}
	if((indexOf(titleActiveImage, "uter"))>= 0) {
		if(activeImageIs=="neither") activeImageIs = "outer";
		else activeImageIs = "neither";
	}			
	Dialog.create("Options for Min-Dist_Solid_Objects_Edge-to-Edge_Stats_Table_and_Add_to_Results macro");
	Dialog.addMessage("This macro version: " + macroL);
	Dialog.addRadioButtonGroup("Direction of minimum distance search:", newArray("Inwards", "Outwards", "Both"),1,2,"Outwards");
	Dialog.addMessage("This macro uses two images as the sources inner and outer objects for the\ndistance measurements. It will try and guess if you have an \"inner\" or \"outer\"\nobjects image open for analysis. The active image is:\n  \n"+titleActiveImage+"\n  \nand is identified as:\n   \n______________ "+activeImageIs+"\n");
	if (activeImageIs=="neither")
		Dialog.addRadioButtonGroup("Is the active image the \"inner\" or the \"outer\"?", newArray("inner", "outer", "neither"), 1,3,"outer");
	Dialog.addMessage("Skipping origin pixels can greatly speed up this macro for very large images.\nTo retain resolution, only the \"from\" x and y pixels will be advanced\nwhereas the \"to\" pixels will be retained for accuracy.\nNote: Both x and y are advanced so a setting of 1 results in 1/4 points.");
	Dialog.addNumber("Number of origin pixels to skip", 0);
	Dialog.addCheckbox("Do you want to include all x and y coordinates in the Distance Table?", true);
	Dialog.addCheckbox("Do you want to also output all minimum distances and coordinates in one 5 column table for use in the line color coder macro?", false);
		
	Dialog.show();
	direction = Dialog.getRadioButton();
	if (activeImageIs=="neither") {
		activeImageIs = Dialog.getRadioButton();
		if (activeImageIs=="neither") {
			Dialog.create("Do you want to open a different file or exit?");
			Dialog.addCheckbox("Open New File?", true);
			Dialog.addRadioButtonGroup("Is the new image \"inner\" or \"outer\"?", newArray("inner", "outer"), 1,3,"outer");
			Dialog.show();
			if((Dialog.getCheckbox())==1) open(); /* if (analyzeNow==true) ImageJ analyze particles will be performed, otherwise exit */
			else restoreExit();
			activeImageIs = Dialog.getRadioButton();
		}
	}
	pxAdv = Dialog.getNumber()+1; /* add 1 so that it can be used directly in the loop incrementals */
	saveCoords = Dialog.getCheckbox();
	colorCoderTable = Dialog.getCheckbox();
			
	print("This macro adds Minimum Distances \(Inlines\) analysis to the Results Table.");
	print("Macro: " + getInfo("macro.filepath"));
	if (direction=="Outwards" || direction=="Both"){
		destAb = "Outw";
		if (direction=="Outwards") destName = "Outw";
		else destName = "Outw&Inw";
	} else {
		destAb = "Inw";
		destName = "Inw";
	}
	print("Distance direction selected to be "+destName+", advancing " + pxAdv + " \"from\" pixels in x and y directions.");
	
	print("Original image: " + titleActiveImage);	 
	imageWidth = getWidth();
	imageHeight = getHeight();
	getPixelSize(unit, pixelWidth, pixelHeight);
	lcf=(pixelWidth+pixelHeight)/2; /* ---> add here the side size of 1 pixel in the new calibrated units (e.g. lcf=5, if 1 pixels is 5mm) <--- */
	print("Original magnification scale factor used = " + lcf + " with units: " + unit);
	/* Guess files to be used from active image name */
	titleActiveImage = getTitle();
	dirActiveImage = getInfo("image.directory");
	lastActiveInner = lastIndexOf(titleActiveImage, "_inner");
	lastActiveOuter = lastIndexOf(titleActiveImage, "_outer");
	if (lastActiveInner>=0) titleSwitch = substring(titleActiveImage,0,lastActiveInner)+"_outer";
	else if (lastActiveOuter>=0) titleSwitch = substring(titleActiveImage,0,lastActiveOuter)+"_inner";
	else titleSwitch = "unknown";
	if (lastActiveInner<0 || activeImageIs=="outer") { /* There was no "_inner" in the active inner name, so the active window is assumed to be "Outer" */
		titleOuterObjects = titleActiveImage;
		print("Active image is assumed to be outer Outline: " + titleOuterObjects);
		titleInnerObjects = titleSwitch;
		pathInnerGuess = dirActiveImage + titleInnerObjects;
		if (File.exists(pathInnerGuess)==true) {
			print(File.exists(pathInnerGuess));
			open(pathInnerGuess);
			print("Image auto-loaded for inner Outline: " + titleInnerObjects);
		}
		else { /* Ask for a file to be imported */
			print("No \"_outer\" - \"_inner\" filename match found");
			fileName = File.openDialog("Select an inner reference \(white\) objects");
			open(fileName);
			titleInnerObjects = getTitle();	 
			print("Image selected for Inner Outline: " + titleInnerObjects);
		}
	}
	else {  /* there was "_inner" in the active image name or inner was specified so active is assumed to "Outer" */
		titleInnerObjects = titleActiveImage; /* Assume that the starting image is inner if it contains "_inner" */
		print("Active image is assumed to be inner Outline: " + titleInnerObjects);
		/* guess outer filename (_inner replaced with _outer) */
		pathOuterGuess = dirActiveImage + titleSwitch;
		if (File.exists(pathOuterGuess)==true) {
			titleOuterObjects = titleSwitch;
			open(pathOuterGuess);	 
			print("Image auto-loaded for outer Outline: " + titleOuterObjects);
		}
		else { /* Ask for a file to be imported */
			print("No \"_outer\" - \"_inner\" filename match found");
			fileName = File.openDialog("Select an inner reference \(white\) objects");
			open(fileName);
			titleOuterObjects = getTitle();	 
			print("Image selected for outer Outline: " + titleOuterObjects);
		}
	}
	binaryCheck(titleInnerObjects);
	binaryCheck(titleOuterObjects); /* See functions: Checks to see if images are in the correct format */
	selectWindow(titleOuterObjects);
	ROIs = checkForRoiManager();
	if (checkForOutlierAreas()) restoreExit("Outlier objects of outlier test fail");
	setBatchMode(true); /* Turn batch mode on */
	start = getTime(); /* Start timer after last requester for debugging. */
	
	selectWindow(titleInnerObjects);
	run("Select None");
	run("Duplicate...", "title=InnerObjectsInLines");
	run("Fill Holes");  /* Just in case */
	run("Outline"); /* InnerObjectsInLines should now be black rings on a white background */

	selectWindow(titleOuterObjects);
	run("Select None");
	run("Duplicate...", "title=OuterObjectsInLines");
	run("Fill Holes");
	run("Outline"); /* OuterObjectsInLines should now be black rings on a white background */
	print("Outer InLine has been generated from hole-filled objects");
	progressWindowTitleS = "Primary_MinDist_Progress"; /* scripts do not need square brackets */
	progressWindowTitle = "[" + progressWindowTitleS + "]";
	run("Text Window...", "name="+ progressWindowTitle +" width=25 height=2 monospaced");
	eval("script","f = WindowManager.getWindow('"+progressWindowTitleS+"'); f.setLocation(50,20); f.setSize(550,150);"); 
	fromCoords = newArray(ROIs);
	toCoords = newArray(ROIs);
	if (saveCoords) {
		fromAllXpoints = newArray(0);
		fromAllYpoints = newArray(0);
		toAllXpoints = newArray(0);
		toAllYpoints = newArray(0);
	}
	allMinDists = newArray(0); /* All measurements are added to a single array to avoid repeated changes to tables */
	loopStart = getTime();
	progressUpdateIntervalCount = 0;
	memoryFlushIntervalCount = 0;
	startRow = 0;
	for (i=0 ; i<ROIs; i++) {
		// showProgress(-i, ROIs);
		selectWindow("InnerObjectsInLines");
		roiManager("select", i);
		Roi.getBounds(ROIx, ROIy, Rwidth, Rheight);
		if ((Rwidth&&Rheight)==1) {
			continue = getBoolean("ROI #" + i + " is an isolated pixel: Do you want to continue?");
			if (!continue) restoreExit("Goodbye");
		}
		run("Duplicate...", "title=InnerObjectInLine"); /* only duplicates ROI */
		run("Clear Outside"); /* Now only the ROI hole outline should be black */
		run("Select None");
		selectWindow("OuterObjectsInLines");
		roiManager("select", i);
		run("Duplicate...", "title=OuterObjectInLine"); /* Generate temporary image that retains ROI selection */
		run("Clear Outside"); /* Now only the ROI-contained object should be black */

		fromXpoints = newArray(0);
		fromYpoints = newArray(0);
		toXpoints = newArray(0);
		toYpoints = newArray(0);

		Label = i+1;
		if (direction=="Outwards" || direction=="Both") /* switch windows for Outward */
			selectWindow("InnerObjectInLine");
		for (x=0; x<Rwidth; x+=pxAdv){ /* Sampling of source data points set by pxAdv */
			for (y=0; y<Rheight; y+=pxAdv){ /* Sampling of source data points set by pxAdv */
				if((getPixel(x, y))==0) { /* Add only black pixels to array. */
					fromXpoints = Array.concat(fromXpoints,x+ROIx);
					fromYpoints = Array.concat(fromYpoints,y+ROIy);
				}
			}
		}
		fromCoords[i] = lengthOf(fromXpoints);
		if (fromCoords[i]==0) restoreExit("Issue with ROI#" + i + ": no From points");
		if (direction=="Outwards" || direction=="Both") /* switch windows for Outward */
			selectWindow("OuterObjectInLine");
		else selectWindow("InnerObjectInLine");
		for (x=0; x<Rwidth; x++){
			for (y=0; y<Rheight; y++){
				if((getPixel(x, y))==0) { /* Add only black pixels to array. */
					toXpoints = Array.concat(toXpoints,x+ROIx);
					toYpoints = Array.concat(toYpoints,y+ROIy);
				}
			}
		}
		toCoords[i] = lengthOf(toXpoints);
		if (toCoords[i]==0) restoreExit("Issue with ROI#" + i + ": no \"To\" points");
		closeImageByTitle("InnerObjectInLine"); /* Reset InLine for each object */
		closeImageByTitle("OuterObjectInLine"); /* Reset InLine for each object */
		
		DZeros = 0;
		D1px = 0;
		minDist = newArray(fromCoords[i]);
		minToX = newArray(fromCoords[i]);
		minToY = newArray(fromCoords[i]);
 
		for  (f=0 ; f<(fromCoords[i]); f++) {
			showProgress(f, fromCoords[i]);
			X1 = fromXpoints[f];
			Y1 = fromYpoints[f];
			minDist[f] = imageWidth+imageHeight; /* just something large enough to be safe */
			for (t=0 ; t<toCoords[i]; t++) {
				X2 = toXpoints[t];
				Y2 = toYpoints[t];
				D = sqrt(pow(X1-X2,2)+pow(Y1-Y2,2));
				if (minDist[f]>D) {
					minDist[f] = D;  /* using this loop is very slightly faster than using array statistics */
					minIndex = t;
				}
			}
			minToX[f] = toXpoints[minIndex];
			minToY[f] = toYpoints[minIndex];
			if (minDist[f]==0) DZeros += 1; /* Dmin is in pixels */
			if (minDist[f]<=1) D1px += 1;
			if (lcf!=1) minDist[f] *= lcf;
		}
		allMinDists = Array.concat(allMinDists, minDist);
		if (saveCoords) {
			fromAllXpoints = Array.concat(fromAllXpoints, fromXpoints);
			fromAllYpoints = Array.concat(fromAllYpoints, fromYpoints);
			toAllXpoints = Array.concat(toAllXpoints, minToX);
			toAllYpoints = Array.concat(toAllYpoints, minToY);
		}
		Array.getStatistics(minDist, Rmin, Rmax, Rmean, Rstd);	
		setResult("From_Points_"+destAb, i, fromCoords[i]);
		setResult("To_Points_"+destAb, i, toCoords[i]);
		if (lcf==1) { 
			setResult("MinDist" + destAb, i, Rmin);
			setResult("MaxDist" + destAb, i, Rmax);
			setResult("Dist" + destAb + "_Mean", i, Rmean);
			setResult("Dist" + destAb + "_Stdv", i, Rstd);
		}
		else {
			setResult("MinDist" + destAb + "\(" + unit + "\)", i, Rmin);
			setResult("MaxDist" + destAb + "\(" + unit + "\)", i, Rmax);
			setResult("Dist" + destAb + "_Mean\(" + unit + "\)", i, Rmean);
			setResult("Dist" + destAb + "_Stdv\(" + unit + "\)", i, Rstd);
		}
		setResult("Dist"+destAb+"_Var\(%\)", i, ((100/Rmean)*Rstd));
		if (DZeros>0) DZeroPC = DZeros*(100/fromCoords[i]);
		else DZeroPC = 0;
		setResult("ZeroDist\(\%\)"+destAb, i, DZeroPC);
		if (D1px>0) D1pxPC = D1px*(100/fromCoords[i]);
		else D1pxPC = 0;
		setResult("0-1PxDist\(\%\)"+destAb, i, D1pxPC);
		
		/* Now add the reverse direction results if "both" directions requested */
		if (direction=="Both") {
			updateResults(); /* Helps stability of "ring" version of this macro so added here as a precaution   �\_(?)_/� */
			DZeros = 0;
			D1px = 0;
			minDist = newArray(toCoords[i]);
			minFromX = newArray(toCoords[i]);
			minFromY = newArray(toCoords[i]);
	 
			for  (t=0 ; t<(toCoords[i]); t++) {
				showProgress(t, toCoords[i]);
				X1 = toXpoints[t];
				Y1 = toYpoints[t];
				minDist[t] = imageWidth+imageHeight; /* just something large enough to be safe */
				for (f=0; f<fromCoords[i]; f++) {
					X2 = fromXpoints[f];
					Y2 = fromYpoints[f];
					D = sqrt(pow(X1-X2,2)+pow(Y1-Y2,2));
					if (minDist[t]>D) {
						minDist[t] = D;  /* using this loop is very slightly faster than using array statistics */
						minIndex = f;
					}
				}
				minFromX[t] = fromXpoints[minIndex];
				minFromY[t] = fromYpoints[minIndex];
				if (minDist[t]==0) DZeros += 1; /* Dmin is in pixels */
				if (minDist[t]<=1) D1px += 1;
				if (lcf!=1) minDist[t] *= lcf;
			}
			allMinDists = Array.concat(allMinDists, minDist);
			if (saveCoords) {
				toAllXpoints = Array.concat(toAllXpoints, toXpoints);
				toAllYpoints = Array.concat(toAllYpoints, toYpoints);
				fromAllXpoints = Array.concat(fromAllXpoints, minFromX);
				fromAllYpoints = Array.concat(fromAllYpoints, minFromY);
			}
			Array.getStatistics(minDist, Rmin, Rmax, Rmean, Rstd);	
			setResult("From_Points_inw", i, toCoords[i]);
			setResult("To_Points_inw", i, fromCoords[i]);
			if (lcf==1) { 
				setResult("MinDist_inw", i, Rmin);
				setResult("MaxDist_inw", i, Rmax);
				setResult("Dist_inw" + "_Mean", i, Rmean);
				setResult("Dist_inw" + "_Stdv", i, Rstd);
			}
			else {
				setResult("MinDist_inw" + "\(" + unit + "\)", i, Rmin);
				setResult("MaxDist_inw" + "\(" + unit + "\)", i, Rmax);
				setResult("Dist_inw" + "_Mean\(" + unit + "\)", i, Rmean);
				setResult("Dist_inw" + "_Stdv\(" + unit + "\)", i, Rstd);
			}
			setResult("Dist_inw_Var\(%\)", i, ((100/Rmean)*Rstd));
			if (DZeros>0) DZeroPC = DZeros*(100/toCoords[i]);
			else DZeroPC = 0;
			setResult("ZeroDist\(\%\)inw", i, DZeroPC);
			if (D1px>0) D1pxPC = D1px*(100/toCoords[i]);
			else D1pxPC = 0;
			setResult("0-1PxDist\(\%\)inw", i, D1pxPC);
		}
		/* End of "both" section */
		if(i==0) {
			loopTime = getTime()-loopStart;
			loopReporting = round(1000/loopTime);  /* set to update only ~ once per second */
		}
		if(progressUpdateIntervalCount==0) {
			timeTaken = getTime()-loopStart;
			timePerLoop = timeTaken/(i+1);
			loopReporting = round(1000/timePerLoop);
			timeLeft = (ROIs-(i+1)) * timePerLoop;
			timeLeftM = floor(timeLeft/60000);
			timeLeftS = (timeLeft-timeLeftM*60000)/1000;
			totalTime = timeTaken + timeLeft;
			/* This macro can consume a lot of memory, the following section tries to flush some of that memory at intervals */
			mem = IJ.currentMemory();
			mem /=1000000;
			memPC = mem*maxMemFactor;
			memIncPerLoop =( memPC-startMemPC)/(i+1);
			memFlushInterval = 10/memIncPerLoop;
			if (memoryFlushIntervalCount > memFlushInterval) {
				memFlush(200);
				memoryFlushIntervalCount = 0;
				flushedMem = IJ.currentMemory();
				flushedMem /=1000000;
				memFlushed = mem-flushedMem;
				memFlushedPC = (100/mem) * memFlushed;
				print(memFlushedPC + "% Memory flushed at " + timeTaken);
			}
			if (memPC>95) restoreExit("Memory use has exceeded 95% of maximum memory");
			print(progressWindowTitle, "\\Update:"+timeLeftM+" m " +timeLeftS+" s to completion ("+(timeTaken*100)/totalTime+"%)\n"+getBar(timeTaken, totalTime)+"\n Current Memory Usage: "  + memPC + "% of MaxMemory: ");
		}
		progressUpdateIntervalCount +=1;
		memoryFlushIntervalCount +=1;
		if (progressUpdateIntervalCount>loopReporting) progressUpdateIntervalCount = 0;
		startRow = fromCoords[i];
	}
	updateResults();
	eval("script","WindowManager.getWindow('"+progressWindowTitleS+"').close();");
	if (isOpen(titleActiveImage)) {
		if (titleActiveImage!=titleInnerObjects) closeImageByTitle(titleInnerObjects);
		if (titleActiveImage!=titleOuterObjects) closeImageByTitle(titleOuterObjects);
		reset();
	}	
	closeImageByTitle("InnerObjectsInLines");
	closeImageByTitle("OuterObjectsInLines");
	roiManager("deselect");
	distanceTableTitle = "Results_" + destName + "_Distances_for_" + ROIs + "_ROIs";
	Table.create(distanceTableTitle);
	startRow = 0;
	endRow = 0;
	for (i=0 ; i<ROIs; i++) {
		endRow = startRow + fromCoords[i];
		if (saveCoords) {
			Table.setColumn("From_X\("+i+"\)", Array.slice(fromAllXpoints,startRow,endRow));
			Table.setColumn("From_Y\("+i+"\)", Array.slice(fromAllYpoints,startRow,endRow));
			Table.setColumn("To_X\("+i+"\)", Array.slice(toAllXpoints,startRow,endRow));
			Table.setColumn("To_Y\("+i+"\)", Array.slice(toAllYpoints,startRow,endRow));
		}
		if (lcf==1) { Table.setColumn("MinDist\(" + i + "\)" + destAb, Array.slice(allMinDists,startRow,endRow));}
		else { Table.setColumn("MinDist\("+i+"\)"+destAb+"\("+unit+"\)", Array.slice(allMinDists,startRow,endRow));}
		startRow = endRow + 1;
		if(direction=="Both") {
			endRow = startRow + toCoords[i];
			if (saveCoords) {
				Table.setColumn("From_X_inw\("+i+"\)", Array.slice(toAllXpoints,startRow,endRow));
				Table.setColumn("From_Y_inw\("+i+"\)", Array.slice(toAllYpoints,startRow,endRow));
				Table.setColumn("To_X_inw\("+i+"\)", Array.slice(fromAllXpoints,startRow,endRow));
				Table.setColumn("To_Y_inw\("+i+"\)", Array.slice(fromAllYpoints,startRow,endRow));
			}
			if (lcf==1) { Table.setColumn("MinDist\(" + i + "\)inw", Array.slice(allMinDists,startRow,endRow));}
			else { Table.setColumn("MinDist\("+i+"\)inw\("+unit+"\)", Array.slice(allMinDists,startRow,endRow));}
			startRow = endRow + 1;
		}
	}
	Table.update;
	if(colorCoderTable) {
		Array.getStatistics(allMinDists, AllMDmin, AllMDmax, AllMDmean, AllMDstdDev);
		AllMDt = "All_" + lengthOf(allMinDists)+ "_" + destName + "_Min_Distances";
		Table.create(AllMDt);
		Table.setColumn("From_X", fromAllXpoints);
		Table.setColumn("From_Y", fromAllYpoints);
		Table.setColumn("To_X", toAllXpoints);
		Table.setColumn("To_Y", toAllYpoints);
		if (lcf==1) {
			Table.setColumn("MinDist", allMinDists);
			print("All Min Dist: Min = "+AllMDmin+", Max = "+AllMDmax+", Mean = " + AllMDmean + ", StdDev = "+ AllMDstdDev + " px")
		}
		else {
			Table.setColumn("MinDist\("+unit+"\)", allMinDists);
			print("All Min Dist: Min = "+AllMDmin+" " +unit+", Max = "+AllMDmax+" " +unit+", Mean = " + AllMDmean +" " +unit+ ", StdDev = "+ AllMDstdDev + " " +unit);
		}
		Table.update;
	}		
	print(ROIs + " objects in = " + (getTime()-start)/1000 + "s");
	print("-----\n\n");
	excelName =  substring(titleActiveImage, 0, lastIndexOf(titleActiveImage, ".")) + "_" + destName;
	if (pxAdv>1) excelName += "_skip"+(pxAdv-1)+"pxls";
	saveExcelFile(dirActiveImage, excelName, distanceTableTitle); /* function saveExcelFile(outputPath, outputName, outputResultsTable) */
	saveExcelFile(dirActiveImage, excelName, "Results");
	if(colorCoderTable) saveExcelFile(dirActiveImage, excelName, AllMDt);
	restoreSettings();
	run("Revert");
	showStatus("Min-Dist macro completed: " + ROIs + " objects in = " + (getTime()-start)/1000 + "s");
	reset();
	setBatchMode("exit & display"); /* exit batch mode */
	memFlush(200);
	/* End of Macro Layer Thickness Macro */
	
	function getBar(p1, p2) {
		/* from https://imagej.nih.gov/ij//macros/ProgressBar.txt */
        n = 20;
        bar1 = "--------------------";
        bar2 = "********************";
        index = round(n*(p1/p2));
        if (index<1) index = 1;
        if (index>n-1) index = n-1;
        return substring(bar2, 0, index) + substring(bar1, index+1, n);
	}
	/*
		( 8(|)	( 8(|)	ASC Functions	@@@@@:-)	@@@@@:-)
	*/
	function binaryCheck(windowTitle) { /* For black objects on a white background */
		/* v180601 added choice to invert or not */
		/* v180907 added choice to revert to the true LUT, changed border pixel check to array stats */
		/* v180925 added window titles to Booleans */
		selectWindow(windowTitle);
		if (is("binary")==0) run("8-bit");
		/* Quick-n-dirty threshold if not previously thresholded */
		getThreshold(t1,t2); 
		if (t1==-1)  {
			run("8-bit");
			run("Auto Threshold", "method=Default");
			run("Convert to Mask");
		}
		if (is("Inverting LUT")==true)  {
			trueLUT = getBoolean("The LUT of " + windowTitle + " appears to be inverted, do you want the true LUT?", "Yes Please", "No Thanks");
			if (trueLUT==true) run("Invert LUT");
		}
		/* Make sure black objects on white background for consistency */
		cornerPixels = newArray(getPixel(0, 0), getPixel(0, 1), getPixel(1, 0), getPixel(1, 1));
		Array.getStatistics(cornerPixels, cornerMin, cornerMax, cornerMean, cornerStdDev);
		if (cornerMax!=cornerMin) restoreExit("Problem with image border: Different pixel intensities at corners");
		/*	Sometimes the outline procedure will leave a pixel border around the outside - this next step checks for this.
			i.e. the corner 4 pixels should now be all black, if not, we have a "border issue". */
		if (cornerMean==0) {
			inversion = getBoolean("The background of " + windowTitle + " appears to have intensity zero, do you want the intensities inverted?", "Yes Please", "No Thanks");
			if (inversion==true) run("Invert"); 
		}
	}
	function checkForOutlierAreas() {
		outliers = true;
		if (nResults>0) {
			sigmas = 6; /* outlier sigmas chosen to be pretty extreme, feel free to adjust this */
			selectWindow("Results");
			Areas =  Table.getColumn("Area");
			if (lengthOf(Areas)==0) showMessage("Outlier check fail", "<html>" +"<font size=+1><font color=red>No Areas in Results Table to check for outliers");
			else {
				Array.getStatistics(Areas, min, max, mean, stdDev);
				if (min<(mean-sigmas*stdDev) || max>(mean+sigmas*stdDev))
						getBoolean("Mean object area = " + mean + ", smallest = " + min + ", largest = " + max + ": Do you want to continue?");
				else outliers=false;
			}
		}
		return outliers;
	}
	function checkForRoiManager() {
		/* v161109 adds the return of the updated ROI count and also adds dialog if there are already entries just in case . .
			v180104 only asks about ROIs if there is a mismatch with the results */
		nROIs = roiManager("count");
		nRES = nResults; /* Used to check for ROIs:Results mismatch */
		if(nROIs==0) runAnalyze = true; /* Assumes that ROIs are required and that is why this function is being called */
		else if(nROIs!=nRES) runAnalyze = getBoolean("There are " + nRES + " results and " + nROIs + " ROIs; do you want to clear the ROI manager and reanalyze?");
		else runAnalyze = false;
		if (runAnalyze) {
			roiManager("reset");
			Dialog.create("Analysis check");
			Dialog.addCheckbox("Run Analyze-particles to generate new roiManager values?", true);
			Dialog.addMessage("This macro requires that all objects have been loaded into the ROI manager.\n \nThere are   " + nRES +"   results.\nThere are   " + nROIs +"   ROIs.");
			Dialog.show();
			analyzeNow = Dialog.getCheckbox();
			if (analyzeNow) {
				setOption("BlackBackground", false);
				if (nResults==0) {
					run("Set Measurements...", "area mean standard modal min centroid center perimeter bounding fit shape feret's integrated median skewness kurtosis area_fraction stack nan redirect=None decimal=9");
					run("Analyze Particles...", "display add");
				}else run("Analyze Particles..."); /* Let user select settings */
				if (nResults!=roiManager("count"))
					restoreExit("Results and ROI Manager counts do not match!");
			}
			else restoreExit("Goodbye, your previous setting will be restored.");
		}
		return roiManager("count"); /* Returns the new count of entries */
	}
	function cleanUp() { /* cleanup leftovers from previous runs */
		closeNonImageByTitle("Results_Distances");
	}
	function closeImageByTitle(windowTitle) {  /* Cannot be used with tables */
		/* v181002 reselects original image at end if open */
		oIID = getImageID();
        if (isOpen(windowTitle)) {
			selectWindow(windowTitle);
			close();
		}
		if (isOpen(oIID)) selectImage(oIID);
	}
	function closeNonImageByTitle(windowTitle) { /* obviously */
	if (isOpen(windowTitle)) {
		selectWindow(windowTitle);
		run("Close");
		}
	}
	function getDateCode() {
		/* v170823 */
		getDateAndTime(year, month, dayOfWeek, dayOfMonth, hour, minute, second, msec);
		month = month + 1; /* Month starts at zero, presumably to be used in array */
		if(month<10) monthStr = "0" + month;
		else monthStr = ""  + month;
		if (dayOfMonth<10) dayOfMonth = "0" + dayOfMonth;
		dateCodeUS = monthStr+dayOfMonth+substring(year,2);
		return dateCodeUS;
	}
	function memFlush(waitTime) {
		
		run("Reset...", "reset=[Undo Buffer]"); 
		wait(waitTime);
		run("Reset...", "reset=[Locked Image]"); 
		wait(waitTime);
		call("java.lang.System.gc"); /* force a garbage collection */
		wait(waitTime);
	}
	function restoreExit(message){ /* Make a clean exit from a macro, restoring previous settings */
		/* 9/9/2017 added Garbage clean up suggested by Luc LaLonde - LBNL */
		restoreSettings(); /* Restore previous settings before exiting */
		setBatchMode("exit & display"); /* Probably not necessary if exiting gracefully but otherwise harmless */
		run("Collect Garbage"); 
		exit(message);
	}
	function saveExcelFile(outputDir, outputName, outputResultsTable) {
	/* v190116 corrected typo in resultsPath */
		selectWindow(outputResultsTable);
		resultsPath = outputDir + outputName + "_" + outputResultsTable + "_" + getDateCode() + ".csv"; /* CSV behaves better with Excel 2016 than XLS */
		if (File.exists(resultsPath)==0)
			saveAs("Results", resultsPath);
		else {
			overWriteFile=getBoolean("Do you want to overwrite " + resultsPath + "?");
			if(overWriteFile==1)
					saveAs("Results", resultsPath);
		}		
	}