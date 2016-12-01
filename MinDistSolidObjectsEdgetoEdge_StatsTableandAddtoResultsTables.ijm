/*	ImageJ Macro to calculate minimum distances between the edges of solid objects in a two-image set.
	One image contains the "inner" object and one the "outer" enclosing object.
	This allows you to analyze objects with broken rings.
 	Inwards or Outwards directions using "In-line".
	6/8/2016 Peter J. Lee (NHMFL)  mod 6/13-29/2016  simplified. Simplified again 8/11-12/2016
*/
	saveSettings(); /* To restore settings at the end */
	snapshot();
	cleanUp(); //function to cleanup old windows (I hope you did not want them). Run before cleanup.
	//roi manager check must be after inner/outer check
	titleActiveImage = getTitle();
	dirActiveImage = getDirectory("image");
	activeImageIs = "neither";
	if((indexOf(titleActiveImage, "inner"))>= 0) {
		activeImageIs = "inner";
	}
	if((indexOf(titleActiveImage, "outer"))>= 0) {
		if(activeImageIs=="neither") activeImageIs = "inner";
		else activeImageIs = "neither";
	}		
		
	Dialog.create("Macro Options");
	Dialog.addCheckbox("Inwards \(otherwise Outwards\)", true);
	Dialog.addMessage("This macro uses two images as the sources inner and outer objects for the\ndistance measurements. It will try and guess if you have an \"inner\" or \"outer\"\nobjects image open for analysis. The active image is:\n"+titleActiveImage+" and is indentified as:\n   \n______________ "+activeImageIs+"\n \n");
	if (activeImageIs=="neither")	Dialog.addRadioButtonGroup("Is active image \"inner\" or \"outer\"?", newArray("inner", "outer", "neither"), 1,3,"outer");
	Dialog.addNumber("Number of origin pixels to skip", 0);
	Dialog.addMessage("Skipping origin pixels can greatly speed up this macro for large images.\nTo retain resolution, only the \"from\" x and y pixels will be advanced\nwhereas the \"to\" pixels will be retained for accuracy.\nNote: Both x and y are advanced so a setting of 1 results in 1/4 points.\n \n");
	if (activeImageIs=="neither")	Dialog.addRadioButtonGroup("Is active image \"inner\" or \"outer\"?", newArray("inner", "outer", "neither"), 1,3,"outer");
	Dialog.addCheckbox("Do you want to include all x and y coordinates in the Distance Table?", true);
		
	Dialog.show();
	direction = Dialog.getCheckbox(); //if (direction==true) distance direction will be inwards;
	if (activeImageIs=="neither") {
		activeImageIs = Dialog.getRadioButton();
		if (activeImageIs=="neither") {
			Dialog.create("Do you want to open a different file or exit?");
			Dialog.addCheckbox("Open New File?", true);
			Dialog.addRadioButtonGroup("Is new image \"inner\" or \"outer\"?", newArray("inner", "outer"), 1,3,"outer");
			Dialog.show();
			if((Dialog.getCheckbox())==1) open(); //if (analyzeNow==true) ImageJ analyze particles will be performed, otherwise exit;
			else restoreExit();
			activeImageIs = Dialog.getRadioButton();
		}
	}
	pxAdv = Dialog.getNumber()+1; // add 1 so that it can be used directly in the loop incrementals
	saveCoords = Dialog.getCheckbox();		
			
	print("\nAdd Minimum Distances \(Inlines\) Stats to Results Table using 32-bit labels");
	print("Macro: " + getInfo("macro.filepath"));
	if (direction==true) destAb = "Inw";
	else  destAb = "Outw";
	print("Distance direction selected to be "+destAb+"ards, advancing " + pxAdv + " \"from\" pixels in x and y directions.");
	
	run("Options...", "iterations=1 count=1 black do=Nothing"); //The binary count setting is set to "1" for consistent outlines
	
	print("Original image: " + titleActiveImage);	 

	imageWidth = getWidth();
	imageHeight = getHeight();
	getPixelSize(unit, pixelWidth, pixelHeight);
	lcf=(pixelWidth+pixelHeight)/2; //---> add here the side size of 1 pixel in the new calibrated units (e.g. lcf=5, if 1 pixels is 5mm) <---

	print("Original magnification scale factor used = " + lcf + " with units: " + unit);

	// Guess files to be used from active image name
	titleActiveImage = getTitle();
	dirActiveImage = getDirectory("image");
	titleSwitch = replace(titleActiveImage, "_inner", "_outer");  // check if active image is inner
	if (titleActiveImage==titleSwitch || activeImageIs=="outer") { // there was no "_inner" in the active inner name so active is assumed to "Outer"
		titleOuterObjects = titleActiveImage;
		print("Active image is assumed to be outer Outline: " + titleOuterObjects);
		titleInnerObjects = replace(titleOuterObjects, "_outer", "_inner");
		if (titleInnerObjects!=titleOuterObjects) {
			pathInnerGuess = dirActiveImage + titleInnerObjects;
			if (File.exists(pathInnerGuess)==1) {
				open(pathInnerGuess);
				print("Image auto-loaded for inner Outline: " + titleInnerObjects);
			}
		}
		else { 		// ask for a file to be imported
			print("No \"_inner\" - \"_outer\" filename match found");
			fileName = File.openDialog("Select an inner reference \(white\) objects");
			open(fileName);
			titleInnerObjects = getTitle();
			print("Image selected for inner Outline: " + titleInnerObjects);
		}
	}
	else {  // there was "_inner" in the active image name or inner was specified so active is assumed to "Outer"
		titleInnerObjects = titleActiveImage; // Assume that starting image is inner if it contains "_inner"
		print("Active image is assumed to be inner Outline: " + titleInnerObjects);
		// guess outer filename (_inner replaced with _outer);		pathOuterObject\titleOuterObjects
		pathOuterGuess = dirActiveImage + titleSwitch;
		if (File.exists(pathOuterGuess)==1) {
			titleOuterObjects = titleSwitch;
			open(pathOuterGuess);
			print("Image auto-loaded for outer Outline: " + titleOuterObjects);
			}
		else { // ask for a file to be imported
			print("No \"_outer\" - \"_inner\" filename match found");
			fileName = File.openDialog("Select an inner reference \(white\) objects");
			open(fileName);
			titleOuterObjects = getTitle();
			print("Image selected for outer Outline: " + titleOuterObjects);
		}
	}
	binaryCheck(titleInnerObjects);
	binaryCheck(titleOuterObjects); // see functions - checks to see if images are in correct format
	selectWindow(titleOuterObjects);
	checkForRoiManager();
	setBatchMode(true); //batch mode on
	start = getTime(); // start timer after last requester for debugging
	selectWindow(titleInnerObjects);
	run("Invert");	// Use invert to make "in-lines" using Outline command below
	run("Outline");

	createLabeledImage();
	
	imageCalculator("Min create 32-bit", titleInnerObjects, "Labeled"); //labeled inner outlined named "Result of "+titleInnerObjects
	selectWindow(titleOuterObjects);
	run("Invert");	// Use invert to make "in-lines" using Outline command below
	run("Outline");
	imageCalculator("Min create 32-bit", titleOuterObjects,"Labeled"); //labeled inner outlined named "Result of "+titleOuterObjects
	
	for (i=0 ; i<roiManager("count"); i++) {
		showStatus("Looping over object " + i + ", " + (roiManager("count")-i) + " more to go");
		selectWindow("Result of " + titleOuterObjects);
		roiManager("select", i);
		Roi.getBounds(Rx, Ry, Rwidth, Rheight);
		fromXpoints = newArray(Rwidth*Rheight);
		fromYpoints = newArray(Rwidth*Rheight);
		toXpoints = newArray(Rwidth*Rheight);
		toYpoints = newArray(Rwidth*Rheight);
		RxEnd = Rx+Rwidth;
		RyEnd = Ry+Rheight;
		Label = i+1;
		
		if (direction==false) // switch windows for Outward
			selectWindow("Result of " + titleInnerObjects);
		pointsRowCounter = 0; //reset row counter
		for (x=Rx; x<RxEnd; x+=pxAdv){
			for (y=Ry; y<RyEnd; y+=pxAdv){
				if((getPixel(x, y))==Label) {  //filter by intensity label
					fromXpoints[pointsRowCounter] = x;
					fromYpoints[pointsRowCounter] = y;
					pointsRowCounter += 1;
				}
			}
		}
		fromXpoints = Array.slice(fromXpoints, 0, pointsRowCounter);
		fromYpoints = Array.slice(fromYpoints, 0, pointsRowCounter);
		
		if (direction==true)
			selectWindow("Result of " + titleInnerObjects);
		if (direction==false)
			selectWindow("Result of " + titleOuterObjects);
			
		pointsRowCounter = 0; //reset row counter
		for (x=Rx; x<RxEnd; x++){
			for (y=Ry; y<RyEnd; y++){
				if((getPixel(x, y)) == Label) {
					toXpoints[pointsRowCounter] = x;
					toYpoints[pointsRowCounter] = y;
					pointsRowCounter += 1;
				}
			}
		}
		toXpoints = Array.slice(toXpoints, 0, pointsRowCounter);
		toYpoints = Array.slice(toYpoints, 0, pointsRowCounter);
		
		if(i==0)   // This swapping of tables does not increase run time significantly
			hideResultsAs("Results_Main");
		else restoreResultsFrom("Results_Distances");
		
		DZeros = 0;
		D1px = 0;
		minDist = newArray(fromXpoints.length);
		for  (fx=0 ; fx<(fromXpoints.length); fx++) {
			showProgress(-fx, fromXpoints.length);
			X1 = fromXpoints[fx];
			Y1 = fromYpoints[fx];
			minDist[fx] = imageWidth+imageHeight; /* just something large enough to be safe */
			minToX = toXpoints[0];
			minToY = toYpoints[0];
			for (j=0 ; j<(toXpoints.length); j++) {
				X2 = toXpoints[j];
				Y2 = toYpoints[j];
				D = sqrt((X1-X2)*(X1-X2)+(Y1-Y2)*(Y1-Y2));
				if (minDist[fx]>D) {
					minDist[fx] = D;  /* using this loop is very slightly faster than using array statistics */
					minToX = X2;
					minToY = Y2;
				}
			}
			if (saveCoords==1) {
				setResult("From_X\("+i+"\)", fx, X1);
				setResult("From_Y\("+i+"\)", fx, Y1);
				setResult("To_X\("+i+"\)", fx, minToX);
				setResult("To_Y\("+i+"\)", fx, minToY);
			}
			if (minDist[fx]==0) DZeros += 1; /* Dmin is in pixels */
			if (minDist[fx]<=1) D1px += 1;
			if (lcf==1) setResult("MinDist\("+i+"\)"+destAb, fx, minDist[fx]);
			else setResult("MinDist\("+i+"\)"+destAb+"\("+unit+"\)", fx, lcf*minDist[fx]);
		}
		if (lcf==1) setResult("MinDist\("+i+"\)"+destAb, fx, "End");
		else setResult("MinDist\("+i+"\)"+destAb+"\("+unit+"\)", fx, "End");
		updateResults();
		
		hideResultsAs("Results_Distances");
		restoreResultsFrom("Results_Main");
		
		Array.getStatistics(minDist, Rmin, Rmax, Rmean, Rstd);
		setResult("From_Points_"+destAb, i, fromXpoints.length);
		setResult("To_Points_"+destAb, i, toXpoints.length);
		if (lcf==1) { 
			setResult("MinDist"+destAb, i, Rmin);
			setResult("MaxDist"+destAb, i, Rmax);
			setResult("Dist"+destAb+"_Mean", i, Rmean);
			setResult("Dist"+destAb+"_Stdv", i, Rstd);
		}
		else {
			setResult("MinDistInw\(" + unit + "\)", i, lcf*Rmin);
			setResult("MaxDistInw\(" + unit + "\)", i, lcf*Rmax);
			setResult("Dist"+destAb+"_Mean\(" + unit + "\)", i, lcf*Rmean);
			setResult("Dist"+destAb+"_Stdv\(" + unit + "\)", i, lcf*Rstd);
		}
		setResult("Dist"+destAb+"_Var\(%\)", i, ((100/Rmean)*Rstd));
		if (Rmin==0) setResult("ZeroDist\(\%\)"+destAb, i, DZeros*(100/fromXpoints.length));
		if (Rmin<=1) setResult("0-1PxDist\(\%\)"+destAb, i, D1px*(100/fromXpoints.length));
		updateResults();
		hideResultsAs("Results_Main");
	}
	restoreResultsFrom("Results_Main");
	if (isOpen(titleActiveImage)) {
		if (titleActiveImage!=titleInnerObjects) closeImageByTitle(titleInnerObjects);
		if (titleActiveImage!=titleOuterObjects) closeImageByTitle(titleOuterObjects);
		reset();
	}	
	closeImageByTitle("Result of " + titleOuterObjects);	
	closeImageByTitle("Result of " + titleInnerObjects);
	closeImageByTitle("Labeled");
	roiManager("deselect");
	
	print(roiManager("count") + " objects in = " + (getTime()-start)/1000 + "s");
	print("-----\n\n");
	
	saveExcelFile(dirActiveImage, titleActiveImage, "Results_Distances"); //function saveExcelFile(outputPath, outputName, outputResultsTable) 
	saveExcelFile(dirActiveImage, titleActiveImage, "Results");

	restoreSettings();
	setBatchMode("exit & display"); /* exit batch mode */
	run("Revert");
	
		
/*-----------functions---------------------*/

	function closeImageByTitle(windowTitle) {  /* cannot be used with tables */
        if (isOpen(windowTitle)) {
		selectWindow(windowTitle);
        close();
		}
	}
	function closeNonImageByTitle(windowTitle) { // obviously
	if (isOpen(windowTitle)) {
		selectWindow(windowTitle);
        run("Close");
		}
	}
	function cleanUp() { //cleanup leftovers from previous runs
		restoreResultsFrom("Results_Main");
		closeNonImageByTitle("Results_Distances");
	}
	function hideResultsAs(deactivatedResults) {
		if (isOpen("Results")) {  // This swapping of tables does not increase run time significantly
			selectWindow("Results");
			IJ.renameResults(deactivatedResults);
		}
	}
	function restoreResultsFrom(deactivatedResults) {
		if (isOpen(deactivatedResults)) {
			selectWindow(deactivatedResults);		
			IJ.renameResults("Results");
		}
	}
	function checkForRoiManager() {
		if (roiManager("count")==0) {
			if (nResults==0) run("Analyze Particles...");
			else {
				Dialog.create("Analysis Choices");
				Dialog.addMessage("ROI object count = " + roiManager("count") + " but Analysis count = " + nResults + ".");
				Dialog.addCheckbox("Run Analyze-particles to new generate roiManager values \(else exit\)?", true);
				Dialog.show();
				analyzeNow = Dialog.getCheckbox(); //if (analyzeNow==true) ImageJ analyze particles will be performed, otherwise exit;
				if (analyzeNow==true) run("Analyze Particles...");
				else restoreExit();
			}
		}
		else if (nResults==0) {
			Dialog.create("Analysis Choices");
			Dialog.addMessage("ROI object count = " + roiManager("count") + " but Analysis count = " + nResults + ".");
			Dialog.addCheckbox("Run Analyze-particles to new generate roiManager values and Results\(else proceed with empty results\)?", false);
			Dialog.show();
			analyzeNow = Dialog.getCheckbox(); //if (analyzeNow==true) ImageJ analyze particles will be performed, otherwise exit;
			if (analyzeNow==true) run("Analyze Particles...");
		}
		else if (roiManager("count")!=nResults && nResults!=0) {
			Dialog.addCheckbox("Do you want to clear the ROI manager and re-run Analyze-particles\(else exit\)?", true);
			Dialog.addMessage("ROI object count = " + roiManager("count") + " but Analysis count = " + nResults + ".");
			analyzeNow = Dialog.getCheckbox(); //if (analyzeNow==true) ImageJ analyze particles will be performed, otherwise exit;
			if (analyzeNow==true) run("Analyze Particles...");
			else restoreExit();
		}
	}
	function binaryCheck(windowTitle) {
		if (isOpen(windowTitle)) {
			selectWindow(windowTitle);
			if (is("binary")==0) run("8-bit");
			// Quick-n-dirty threshold if not previously thresholded
			getThreshold(t1,t2); 
			if (t1==-1)  {
				run("8-bit");
				setThreshold(0, 128);
				setOption("BlackBackground", false);
				run("Convert to Mask");
				run("Invert");
				}
			// Make sure white objects on black background for consistency	
			if (((getPixel(0, 0))!=0 || (getPixel(0, 1))!=0 || (getPixel(1, 0))!=0 || (getPixel(1, 1))!=0))
				run("Invert"); 
			// Sometimes the outline procedure will leave a pixel border around the outside - this next step checks for this.
			// i.e. the corner 4 pixels should now be all black, if not, we have a "border issue".
			if (((getPixel(0, 0))+(getPixel(0, 1))+(getPixel(1, 0))+(getPixel(1, 1))) != 0 ) 
					restoreExit("Border Issue"); 	
		}
	}
	function createLabeledImage() {
		newImage("Labeled", "32-bit black", imageWidth, imageHeight, 1);
		for (i=0 ; i<roiManager("count"); i++) {
			roiManager("select", i);
			setColor(1+i);
			fill(); /* This only only works for 32-bit images so hopefully it is not a bug */
		}
	}
	function saveExcelFile(outputDir, outputName, outputResultsTable) {
		selectWindow(outputResultsTable);
		resultsPath = outputDir + outputName + "_" + outputResultsTable + "_" + destAb + "_" + getDateCode() + ".xls";
		if (File.exists(resultsPath)==0)
			saveAs("results", resultsPath);
		else {
			overWriteFile=getBoolean("Do you want to overwrite " + resultsPath + "?");
			if(overWriteFile==1)
					saveAs("results", resultsPath);
		}		
	}
	function getDateCode() {
		/* v161107 */
		 getDateAndTime(year, month, dayOfWeek, dayOfMonth, hour, minute, second, msec);
		 month = month + 1; /* month starts at zero, presumably to be used in array */
		 if(month<10) monthStr = "0" + month;
		 else monthStr = ""  + month;
		 if (dayOfMonth<10) dayOfMonth = "0" + dayOfMonth;
		 dateCodeUS = "_"+monthStr+dayOfMonth+substring(year,2);
		 return dateCodeUS;
     }
	 function restoreExit(message){ // clean up before aborting macro then exit
		restoreSettings(); //clean up before exiting
		setBatchMode("exit & display"); // not sure if this does anything useful if exiting gracefully but otherwise harmless
		exit(message);
	}