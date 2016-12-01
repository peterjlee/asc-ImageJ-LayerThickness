//	ImageJ Macro to calculate minimum distances:
// 	Wall thickness where each object is hollow (inwards or outwards using "In-lines")
//	6/7/2016 Peter J. Lee (NHMFL), simplified 6/13-28/2016

	saveSettings(); /* To restore settings at the end */
	snapshot();
	cleanUp(); // Before ROI mamager check
	titleOuterObjects = getTitle();
	dirOuterObjects = getDirectory("image");
	binaryCheck(titleOuterObjects);
	checkForRoiManager();
	
	Dialog.create("Macro Options");
	directions = newArray("Inwards", "Outwards");
	Dialog.addRadioButtonGroup("Direction", directions, 1, 2, "Inwards"); 
	Dialog.addNumber("Number of origin pixels to skip", 0);
	Dialog.addMessage("Only the \"from\" x and y pixels will be advanced\n the \"to\" pixels will be retained for accuracy.\n Note: Both x and y are advanced so a setting of 1 results in 1/4 points.");
	Dialog.show();
	direction = Dialog.getRadioButton();
	pxAdv = Dialog.getNumber() + 1; // add 1 so that "skip" alone can be used in loop incremental
	print("\nRings-Add Minimum Distances \(Inlines\) Stats to Results Tables using Gray Labels Macro");
	print("Macro: " + getInfo("macro.filepath"));

	if (direction=="Inwards") destAb = "Inw";
	else  destAb = "Outw";
	print("Distance direction selected to be "+destAb+"ards, advancing " + pxAdv + " \"from\" pixels in x and y directions.");

	start = getTime(); // start timer after last requester for debugging
	run("Options...", "iterations=1 count=1 black do=Nothing"); //The binary count setting is set to "1" for consistent outlines
	setBatchMode(true);

	print("Image used for outer inlines: " + titleOuterObjects);	 
	
	imageWidth = getWidth();
	imageHeight = getHeight();
	getPixelSize(unit, pixelWidth, pixelHeight);

	lcf=(pixelWidth+pixelHeight)/2; //---> add here the side size of 1 pixel in the new calibrated units (e.g. lcf=5, if 1 pixels is 5mm) <---

	print("Original magnification scale factor that will be used = " + lcf + " with units: " + unit);
	run("Select None");
	run("Duplicate...", "title=HoleInLines"); // name a little confusing at this stage but this is what it will become
	run("Fill Holes");

	createLabeledImage();
	
	imageCalculator("XOR", "HoleInLines", titleOuterObjects); 	//Generates solid core
	run("Invert");	// Use invert to make "in-lines" from outline
	run("Outline");
	print("Inner InLine is generated from hole in ring");
	imageCalculator("Min create 32-bit", "HoleInLines","Labeled"); //labeled inner outlined named "Result of HoleInLines"
	selectWindow(titleOuterObjects);
	run("Select None");
	run("Duplicate...", "title=OuterInLines");
	run("Fill Holes");
	run("Invert");	// Use invert to make "in-lines" from outline
	run("Outline");
	imageCalculator("Min create 32-bit", "OuterInLines","Labeled");  //labeled inner outlined named "Result of OuterInLines"

	for (i=0 ; i<roiManager("count"); i++) {
		showStatus("Looping over object " + i + ", " + (roiManager("count")-i) + " more to go");
		selectWindow("Result of OuterInLines");
		roiManager("select", i);
		Label = i+1;
		Roi.getBounds(Rx, Ry, Rwidth, Rheight);
		fromXpoints = newArray(Rwidth*Rheight);
		fromYpoints = newArray(Rwidth*Rheight);
		toXpoints = newArray(Rwidth*Rheight);
		toYpoints = newArray(Rwidth*Rheight);
		RxEnd = Rx+Rwidth;
		RyEnd = Ry+Rheight;

		pointsRowCounter = 0;
		if (destAb=="Outw") // if "Outwards" was selected
			selectWindow("Result of HoleInLines");
		for (x=Rx; x<RxEnd; x+=pxAdv){
			for (y=Ry; y<RyEnd; y+=pxAdv){
				if((getPixel(x, y))==Label) {
					fromXpoints[pointsRowCounter] = x;
					fromYpoints[pointsRowCounter] = y;
					pointsRowCounter += 1;
				}
			}
		}
		/* trim arrays using row count to future proof for IJ2"s lack of expandable arrays */
		fromXpoints = Array.slice(fromXpoints, 0, pointsRowCounter);
		fromYpoints = Array.slice(fromYpoints, 0, pointsRowCounter);	
		
		pointsRowCounter = 0; //reset row counter
		if (destAb=="Outw") // if "Outwards" was selected
			selectWindow("Result of OuterInLines");
		else selectWindow("Result of HoleInLines");
		for (x=Rx; x<RxEnd; x++){
			for (y=Ry; y<RyEnd; y++){
				if((getPixel(x, y))==Label) {
					toXpoints[pointsRowCounter] = x;
					toYpoints[pointsRowCounter] = y;
					pointsRowCounter += 1;
				}
			}
		}
		toXpoints = Array.slice(toXpoints, 0, pointsRowCounter);
		toYpoints = Array.slice(toYpoints, 0, pointsRowCounter);
		/* if the ring is broken the arrays size will be zero */
	
		if(i==0) hideResultsAs("Results_Main");
		else restoreResultsFrom("Results_Distances");
		
		DZeros = 0;
		D1px = 0;
		minDist = newArray(fromXpoints.length);
		if (fromXpoints.length>=1 && toXpoints.length>=1) { /*  check if ring is broken */	
			for  (fx=0 ; fx<(fromXpoints.length); fx++) {   
				showProgress(-fx, fromXpoints.length);
				X1 = fromXpoints[fx];
				Y1 = fromYpoints[fx];
				minDist[fx] = imageWidth+imageHeight; /* just something large enough to be safe */
				for (j=0 ; j<(toXpoints.length); j++) {
					X2 = toXpoints[j];
					Y2 = toYpoints[j];
					D = sqrt((X1-X2)*(X1-X2)+(Y1-Y2)*(Y1-Y2));
					if (minDist[fx]>D) minDist[fx] = D;  /* using this loop is very slightly faster than using array statistics */
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
				setResult("MinDist"+destAb+"\(" + unit + "\)", i, lcf*Rmin);
				setResult("MaxDist"+destAb+"\(" + unit + "\)", i, lcf*Rmax);
				setResult("Dist"+destAb+"_Mean\(" + unit + "\)", i, lcf*Rmean);
				setResult("Dist"+destAb+"_Stdv\(" + unit + "\)", i, lcf*Rstd);
			}
			setResult("Dist"+destAb+"_Var\(%\)", i, ((100/Rmean)*Rstd));
			if (Rmin<=1) setResult("1PxDist\(\%\)"+destAb, i, D1px*(100/fromXpoints.length));
		} /* close of non-broken ring loop */
		else { /* if no from or to points (open) . . . */ 
			if (lcf==1) setResult("MinDist\("+i+"\)"+destAb, 0, "Open");
			else setResult("MinDist\("+i+"\)"+destAb+"\("+unit+"\)", 0, "Open");
			updateResults();
			hideResultsAs("Results_Distances");
			restoreResultsFrom("Results_Main");
			setResult("From_Points_"+destAb, i, fromXpoints.length);
			setResult("To_Points_"+destAb, i, toXpoints.length);	
			if (lcf==1) { 
				setResult("MinDist"+destAb, i,  "Open");
				setResult("MaxDist"+destAb, i,  "Open");
				setResult("Dist"+destAb+"_Mean", i,  "Open");
				setResult("Dist"+destAb+"_Stdv", i,  "Open");
			}
			else {
				setResult("MinDist"+destAb+"\(" + unit + "\)", i,  "Open");
				setResult("MaxDist"+destAb+"\(" + unit + "\)", i,  "Open");
				setResult("Dist"+destAb+"_Mean\(" + unit + "\)", i,  "Open");
				setResult("Dist"+destAb+"_Stdv\(" + unit + "\)", i,  "Open");
			}
			setResult("Dist"+destAb+"_Var\(%\)", i, "Open");
			setResult("0-1PxDist\(\%\)"+destAb, i, "Open");
		} /* end of broken loop */
		updateResults();
		hideResultsAs("Results_Main");	
	}
	/* Now for some cleanup at the end */
	restoreResultsFrom("Results_Main");		
	closeImageByTitle("Result of HoleInLines");
	closeImageByTitle("Result of OuterInLines");
	closeImageByTitle("OuterInLines");
	closeImageByTitle("Labeled");
	closeImageByTitle("HoleInLines");
	roiManager("deselect");

	print(roiManager("count") + " objects in = " + (getTime()-start)/1000 + "s");
	print("-----\n\n");
	
	saveExcelFile(dirOuterObjects, titleOuterObjects, "Results_Distances"); //function saveExcelFile(outputPath, outputName, outputResultsTable) 
	saveExcelFile(dirOuterObjects, titleOuterObjects, "Results");

	restoreSettings();
	reset();
	setBatchMode("exit & display"); /* exit batch mode */
	
	//-----------functions---------------------

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