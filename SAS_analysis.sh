#!/bin/bash


# This script is used to do the basic steps in EPIC data reduction as the follows:
# 1- initialize SAS
# 2- prepare the raw data odf
# 3- make the CCF and ODF summary file
# 4- rerun the pipeline
# 5- create the light curve
# 6- filter the event file
# 7- create sky images 


#--------------------------------------------------------------------------
#                             1- initialize  SAS10
#--------------------------------------------------------------------------

#if [ $1 ] ;
#then 
    mypath=$PWD 
#else 
#    echo "Usage: $0 <insert working_directory>"; 
#    exit 0
#fi


cat << EOF
**********************************************************
1 - Initialising SAS
**********************************************************
EOF

source /net/konraid/xray/xraysoft/setheasoft.sh

source /net/konraid/xray/xraysoft/setxmmsas.sh
export SAS_CCFPATH=/net/konraid/xray/xraysoft/xmmsas/ccf/

sasversion

echo "Insert directory with the data"
read obs

cd $obs
#--------------------------------------------------------------------------
#                               LOOP
#--------------------------------------------------------------------------

for archive in `ls *.tar` ;
do
obsid=`tar -tf "$archive" | head -n 2 | tail -n 1 | tr -d '/.'`;
done

echo $obsid


#----------------------------------------------------------------------------
#                             2- prepare the raw data odf
#----------------------------------------------------------------------------
cat << EOF
**********************************************************
2 - prepare the raw data odf
**********************************************************
EOF

#uncompress the files
tar -xvf *.tar

echo "in directory " $obsid

cd $obsid/odf
tar -zxvf *.tar.gz
tar -xvf *.TAR
rm *.tar.gz
rm *.TAR

#Setting ODF and CCF

#point to an ODF
odfpath=`pwd`
export SAS_ODF=$odfpath
echo "SAS_ODF=$SAS_ODF"

#----------------------------------------------------------------------------
#                             3- make the CCF and ODF summary file
#----------------------------------------------------------------------------

#generating and pointing to a Calibration Index File (CIF)

cat << EOF
**********************************************************
cifbuild
**********************************************************
EOF

#rm ccf.cif
cifbuild
export SAS_CCF=$odfpath/ccf.cif
echo "SAS_CCF=$SAS_CCF"

#prepare the data and produce the summary file

cat << EOF
**********************************************************
odfingest
**********************************************************
EOF

#rm *SUM.SAS
odfingest
sumfile=`ls -t *SUM.SAS | head -1`
export SAS_ODF=$odfpath/$sumfile
echo "SAS_ODF=$SAS_ODF"
sasversion

#-------------------------------------------------------------------------
#                             4- rerun the pipeline
#------------------------------------------------------------------------

#produce calibrated photon event files for PN and MOS.
#run the pipeline processing

#create a result directory for each detid

cd $mypath
mkdir -p pps/$obsid/epic/pn
mkdir -p pps/$obsid/epic/mos
mkdir -p pps/$obsid/timing
mkdir -p pps/$obsid/spectra
mkdir -p pps/$obsid/rgs
mkdir -p pps/$obsid/om
mkdir -p pps/$obsid/om/image
mkdir -p pps/$obsid/om/timing
mkdir -p pps/$obsid/OoT
mkdir -p pps/$obsid/epatplot

cd pps/$obsid/OoT

cat << EOF
**********************************************************
EPIC PN Out-of-Time events in pps/$obsid/OoT
**********************************************************
EOF

epchain runbackground=N keepintermediate=raw withoutoftime=Y

epchain runatthkgen=N runepframes=N runbadpixfind=N runbadpix=N

evselect table=`ls -t *OOEVLI*.FIT` imagebinning=binSize \
  imageset=PN_OoT_image.fits withimageset=yes xcolumn=X ycolumn=Y \
  ximagebinsize=80 yimagebinsize=80

evselect table=`ls -t *PIEVLI*.FIT` imagebinning=binSize \
  imageset=PN_observation_image.fits withimageset=yes xcolumn=X ycolumn=Y \
  ximagebinsize=80 yimagebinsize=80

farith PN_OoT_image.fits 0.063 PN_OoT_image_rescaled.fits MUL

farith PN_observation_image.fits PN_OoT_image_rescaled.fits \
  PN_observation_clean_image.fits SUB

cd pps/$obsid/epic/pn

cat << EOF
**********************************************************
EPIC PN PIPELINE in pps/$obsid/epic/pn
**********************************************************
EOF

epproc >& epproc.log

#define the name of the input calibrated event list as a variable
#pn event list
if [[ `ls -l *EPN*ImagingEvts.ds | wc -l` -gt 1 ]]; then 
  PS3="More than one event file detected. Type a number or 'q' to quit: "
  fv *EPN*ImagingEvts.ds
  select PNevfile in *EPN*ImagingEvts.ds;
  do	
    if [ -n "$PNevfile" ]; then
       echo "$PNevfile chosen "
    fi
       break;
  done
else 
 PNevfile=`ls *EPN*ImagingEvts.ds`
 fv $PNevfile &
fi




cat << EOF
**********************************************************
Images in 5 energy bands
**********************************************************
EOF

#extract single event (i.e. pattern zero only), high energy (E > 10 keV) light curves, to identify intervals of flaring particle background

evselect table=$PNevfile:EVENTS expression='#XMMEA_EP&&(PI>10000)&&(PATTERN==0)' \
  rateset="pn_back_lightc.fits" timebinsize=10 withrateset=yes \
  maketimecolumn=yes makeratecolumn=yes  2>&1

 
#plot the light curves to decide about the cut to be applied for rejection of flaring periods
dsplot table=pn_back_lightc.fits x=TIME y=RATE   2>&1 &

threshold1=1.0
echo "Type a Low background threshold or press ENTER to use the default recommended value (1.0 [cts/s])" >&2
read newthreshold1
[ -n "$newthreshold1" ] && threshold1=$newthreshold1

#establish Good Time Intervals (GTIs) for every camera, since exposure coverage can be different
tabgtigen table=pn_back_lightc.fits \
	    expression="RATE.le.${threshold1}" \
	    gtiset=pn_back_gti.fits     2>&1



cat << EOF
**********************************************************
EPIC source finding
**********************************************************
EOF

#Produce images for PN in 5 energy bands and from the whole spectral coverage

evselect table=$PNevfile:EVENTS imagebinning='binSize' imageset='pn_image_full.fits' \
  withimageset=yes xcolumn='X' ycolumn='Y' ximagebinsize=80 yimagebinsize=80 \
  expression='#XMMEA_EP&&(PI in [300:12000])&&(PATTERN in [0:4])&&(FLAG==0) && gti(pn_back_gti.fits,TIME)'

evselect table=$PNevfile:EVENTS  imagebinning='binSize' imageset='pn_image_b1.fits' \
  withimageset=yes xcolumn='X' ycolumn='Y' ximagebinsize=80 yimagebinsize=80 \
  expression='#XMMEA_EP&&(PI in [300:500])&&(PATTERN in [0:4])&&(FLAG==0) && gti(pn_back_gti.fits,TIME)'

evselect table=$PNevfile:EVENTS  imagebinning='binSize' imageset='pn_image_b2.fits' \
  withimageset=yes xcolumn='X' ycolumn='Y' ximagebinsize=80 yimagebinsize=80 \
  expression='#XMMEA_EP&&(PI in [500:1000])&&(PATTERN in [0:4])&&(FLAG==0) && gti(pn_back_gti.fits,TIME)'

evselect table=$PNevfile:EVENTS  imagebinning='binSize' imageset='pn_image_b3.fits' \
  withimageset=yes xcolumn='X' ycolumn='Y' ximagebinsize=80 yimagebinsize=80 \
  expression='#XMMEA_EP&&(PI in [1000:2000])&&(PATTERN in [0:4])&&(FLAG==0) && gti(pn_back_gti.fits,TIME)'

evselect table=$PNevfile:EVENTS  imagebinning='binSize' imageset='pn_image_b4.fits' \
  withimageset=yes xcolumn='X' ycolumn='Y' ximagebinsize=80 yimagebinsize=80 \
  expression='#XMMEA_EP&&(PI in [2000:4500])&&(PATTERN in [0:4])&&(FLAG==0) && gti(pn_back_gti.fits,TIME)'

evselect table=$PNevfile:EVENTS  imagebinning='binSize' imageset='pn_image_b5.fits' \
  withimageset=yes xcolumn='X' ycolumn='Y' ximagebinsize=80 yimagebinsize=80 \
  expression='#XMMEA_EP&&(PI in [4500:12000])&&(PATTERN in [0:4])&&(FLAG==0) && gti(pn_back_gti.fits,TIME)'

#Run detection chains for all

edetect_chain imagesets='"pn_image_b1.fits" "pn_image_b2.fits" "pn_image_b3.fits" "pn_image_b4.fits" "pn_image_b5.fits"' \
  eventsets=$PNevfile attitudeset=`ls  -1 *AttHk.ds*` \
  pimin='300 500 1000 2000 4500' pimax='500 1000 2000 4500 12000' \
  ecf='8.970 6.596 1.953 0.941 0.240' \
  eboxl_list='pn_eboxlist_l.fits' eboxm_list='pn_eboxlist_m.fits' \
  esp_nsplinenodes=16 eml_list='pn_emllist.fits' esen_mlmin=15


#Display the detected source on top the full energy bandpass image
srcdisplay boxlistset=pn_emllist.fits imageset=pn_image_full.fits sourceradius=0.01 &


evselect table=$PNevfile:EVENTS withimageset=yes \
	      imageset=pn-unfilt.im xcolumn=X ycolumn=Y \
	      imagebinning=binSize ximagebinsize=80 yimagebinsize=80      2>&1

ds9 -cmap bb -scale sqrt -geometry 650x850 \
		  pn-unfilt.im 	  2>&1 &


#echo "Enter Source coordinates and radius (in ds9 Physical mode) (e.g. 20546.5 22667.5 600):" >&2
#read srcX srcY rad

#region eventset=$PNevfile:EVENTS operationstyle=global \
#	      radiusstyle=userfixed fixedradius=30 \
#	      expression="ID_BAND.eq.0" srclisttab=pn_emllist.fits \
#	      bkgregionset=pn-filt-bkg.reg   2>&1
#evselect table=$PNevfile \
#	      expression="region(pn-filt-bkg.reg,X,Y) .and. .not. (circle($srcX,$srcY,$rad,X,Y))" \
#	      filteredset="pn-filt-bkg.ev" updateexposure=N writedss=N \
#	      withfilteredset=Y destruct=Y keepfilteroutput=Y   2>&1
#evselect table=pn-filt-bkg.ev:EVENTS withimageset=yes \
#	      imageset=pn-filt-bkg.im xcolumn=X ycolumn=Y \
#	      imagebinning=imageSize ximagesize=600 yimagesize=600      2>&1


# Create background light curves to check for flaring
# bkg-cheese.ra: source free background
# flare.ra:      events > 10keV

#evselect table=pn-filt-bkg.ev:EVENTS withrateset=yes \
#	  rateset=pn-bkg-cheese.ra timecolumn=TIME makeratecolumn=yes \
#	  timebinsize=10 maketimecolumn=yes  2>&1

#dsplot table=pn-bkg-cheese.ra x=TIME y=RATE   2>&1 &      # end cheesed images (only imaging mode)

#------------------------------------------------------------------------------
#                             5- create the light curve
#------------------------------------------------------------------------------
#                             PN light curve
#-----------------------------------------------------------------------------

# now: imaging & timing mode

cat << EOF
**********************************************************
Check PN background for flaring
**********************************************************
EOF


#Create a light-curve for the observation to check for flaring high background periods (pn)

evselect table=$PNevfile:EVENTS withrateset=yes \
	rateset=pn-flare.ra timecolumn=TIME \
	makeratecolumn=yes timebinsize=100 maketimecolumn=yes \
	filtertype=expression \
	expression='#XMMEA_EP && (PI>10000&&PI<12000) && (PATTERN==0)'     2>&1

    AGAIN="y"
    until [ $AGAIN = "n" ] ;   do       # begin repeat background threshold


## Display the light curve 
fplot table=pn-flare.ra TIME RATE[ERROR] - /xs - 

echo "How do you want to select Good Time Intervals? Type TIME or RATE:"
read gti_select

if [ $gti_select = "RATE" ]; then
  threshold=0.4
  echo "Type a Low background threshold or press ENTER to use the default recommended value for PN (0.4 [cts/s])" 
  read newthreshold
  [ -n "$newthreshold" ] && threshold=$newthreshold1
  tabgtigen table=pn-flare.ra expression="RATE.le.${threshold}" gtiset=pn-flare.gti 2>&1
else
  if [ $gti_select = "TIME" ]; then
    echo "Type the TIME value where the low-background begins:"
    read time_thres
    tabgtigen table=pn-flare.ra gtiset=pn-flare.gti expression="TIME.ge.${time_thres}" timecolumn=TIME 2>&1
    fi
fi   

#------------------------------------------------------------------------------
#                             6- filter the event file
#------------------------------------------------------------------------------
#                             PN filtered event file
#------------------------------------------------------------------------------

#cat << EOF
#**********************************************************
#Filtering PN background
#**********************************************************
#EOF

#evselect table=pn-filt-bkg.ev:EVENTS withfilteredset=yes \
#	expression="gti(pn-flare.gti,TIME)" \
#	filteredset=pn-bkg-gti.ev filtertype=expression \
#	keepfilteroutput=yes    2>&1


#Create a new light curve to make sure that the flaring background time intervals were removed:

#cat << EOF
#**********************************************************
#Creating background light curves
#**********************************************************
#EOF

#evselect table=pn-bkg-gti.ev:EVENTS withrateset=yes \
#	rateset=pn-bkg-gti.ra timecolumn=TIME \
#	makeratecolumn=yes timebinsize=10 maketimecolumn=yes 2>&1

## Display the new light curves

#dsplot table=pn-bkg-gti.ra x=TIME y=RATE   2>&1 &


cat << EOF
**********************************************************
Filtering data with selected gti
**********************************************************
EOF

evselect table=$PNevfile:EVENTS \
	    expression="#XMMEA_EP && (PI in [100:15000]) && gti(pn-flare.gti,TIME) &&(PATTERN in [0:4])&&(FLAG==0)" \
	    withfilteredset=yes filteredset=pn-filt.ev \
	    filtertype=expression keepfilteroutput=yes         2>&1

evselect table=pn-filt.ev:EVENTS withrateset=yes \
	rateset=pn-flare_after_gti.ra timecolumn=TIME \
	makeratecolumn=yes timebinsize=100 maketimecolumn=yes \
	filtertype=expression \
	expression='#XMMEA_EP && (PI>10000&&PI<12000) && (PATTERN==0)'  2>&1

## Display the light curve 
dsplot table=pn-flare_after_gti.ra x=TIME y=RATE   2>&1 &

echo "Try new background threshold? (y/n)" >&2
read AGAIN

# end repeat background threshold
done

#------------------------------------------------------------------------------
#                             7- create the sky images of the filtered data
#                             8- select src and bkg regions
#------------------------------------------------------------------------------
#                             PN sky image & select src and bdg regions
#-----------------------------------------------------------------------------
cat << EOF
**********************************************************
Create a sky image of the filtered data set
**********************************************************
EOF


evselect table=pn-filt.ev:EVENTS withimageset=yes \
	      imageset=pn-filt.im xcolumn=X ycolumn=Y \
	      imagebinning=binSize ximagebinsize=80 yimagebinsize=80      2>&1

ds9 -cmap bb -scale sqrt -geometry 650x850 \
		  pn-filt.im 	  2>&1 &


cat << EOF
**********************************************************
Extraction of SPECTRUM and LIGHT CURVE
**********************************************************
EOF

echo "Select PN source and background regions in ds9, save the regions as "pn-source.reg" and "pn-back.reg" in ds9 Physical mode and press ENTER"

read

pnsrc=`cat pn-source.reg | tail -n 1`
pnbkg=`cat pn-back.reg | tail -n 1`


eregionanalyse imageset=pn-filt.im srcexp="(X,Y) IN $pnsrc" backexp="(X,Y) IN $pnbkg" | tee eregionanalyse_pn.log

nsrcX=`cat eregionanalyse_pn.log | grep SASCIRCLE | tr -d 'SASCIRCLE: in CIRCLE X Y ()' | awk -F ',' '{ print $2 }'`
nsrcY=`cat eregionanalyse_pn.log | grep SASCIRCLE | tr -d 'SASCIRCLE: in CIRCLE X Y ()' | awk -F ',' '{ print $3 }'`
nsrcrad=`cat eregionanalyse_pn.log | grep SASCIRCLE | tr -d 'SASCIRCLE: in CIRCLE X Y ()' | awk -F ',' '{ print $4 }'`

echo "You have selected the following source region: $pnsrc \
eregionanalyse suggests to use ($nsrcX,$nsrcY,$nsrcrad) as optimal coordinates for source extraction. Do you want to use the suggested coordinates? (y/n)" >&2
read ANSWER

if [ $ANSWER = "y" ]; then
      pnsrc="circle($nsrcX,$nsrcY,$nsrcrad)"
      echo "New source: $pnsrc. Do you want to change the background radius? (It's recommended to select a radius which is at least 2 x source radius) (y/n)"
      read ans2
      if [ $ans2 = "y" ]; then
	  ds9 pn-filt.im -cmap bb -scale sqrt -geometry 650x850 -region pn-back.reg	 2>&1 &
	  echo "Select a new background region in ds9, save the region as "pn-back-2.reg" in ds9 Physical mode and press ENTER"
	  read
	  pnbkg=`cat pn-back-2.reg | tail -n 1`
      fi
else
    if [ $ANSWER = "n" ]; then
      pnsrc=$pnsrc
    fi
fi

echo "Source will be extracted in $pnsrc and background: $pnbkg"

cp pn-flare.gti $mypath/pps/$obsid/epatplot
cp pn-filt.ev $mypath/pps/$obsid/epatplot
cp pn-filt.ev $mypath/pps/$obsid/timing
cp pn-filt.ev $mypath/pps/$obsid/spectra

cd $mypath/pps/$obsid/epatplot

cat << EOF
**********************************************************
Evaluation of pile-up in $mypath/pps/$obsid/epatplot
**********************************************************
EOF

evselect table=pn-filt.ev withfilteredset=yes filteredset=pn_filtered.evt \
   keepfilteroutput=yes expression="((X,Y) IN ${pnsrc}) && gti(pn-flare.gti,TIME)" 

epatplot set=pn_filtered.evt plotfile="pn_filtered_pat.ps"


cat << EOF
**********************************************************
Creating PN light curve in $mypath/pps/$obsid/timing
**********************************************************
EOF

cd $mypath/pps/$obsid/timing

barycen table=pn-filt.ev:EVENTS

   tbAGAIN="y"
   until [ $tbAGAIN = "n" ] ;   do       # begin repeat background threshold

ntb_pn=100
echo "Choose a time bin size for PN light curve or press ENTER to use the default value (100 s):"
read newntb_pn
[ -n "$newntb_pn" ] && ntb_pn=$newntb_pn

evselect table=pn-filt.ev energycolumn=PI expression="#XMMEA_EP&&(PATTERN<=4) && ((X,Y) IN ${pnsrc}) && (PI in [200:10000])" \
    withrateset=yes rateset="pn_source_lightcurve_raw.lc" timebinsize=${ntb_pn} \
    maketimecolumn=yes makeratecolumn=yes 

evselect table=pn-filt.ev energycolumn=PI expression="#XMMEA_EP&&(PATTERN<=4) && ((X,Y) IN ${pnbkg}) && (PI in [200:10000])" withrateset=yes \
   rateset="pn_back_lightcurve_raw.lc" timebinsize=${ntb_pn} \
   maketimecolumn=yes makeratecolumn=yes 

epiclccorr srctslist=pn_source_lightcurve_raw.lc eventlist=pn-filt.ev outset=pn${ntb_pn}-lccorr.lc bkgtslist=pn_back_lightcurve_raw.lc withbkgset=yes applyabsolutecorrections=yes

dsplot table=pn${ntb_pn}-lccorr.lc withx=yes x=TIME withy=yes y=RATE &

echo "Try new time bin size? (y/n)" >&2
read tbAGAIN

# end repeat 
done

cat << EOF
**********************************************************
Creating PN spectrum in $mypath/pps/$obsid/spectra
**********************************************************
EOF

cp pn-filt.ev $mypath/pps/$obsid/spectra
cd $mypath/pps/$obsid/spectra

evselect table=pn-filt.ev withspectrumset=yes spectrumset=pn-source.pi \
  energycolumn=PI spectralbinsize=5 withspecranges=yes specchannelmin=0 specchannelmax=20479 \
  expression="(FLAG==0) && (PATTERN<=4) && ((X,Y) IN ${pnsrc})"


evselect table=pn-filt.ev withspectrumset=yes spectrumset=pn-background.pi \
   energycolumn=PI spectralbinsize=5 withspecranges=yes specchannelmin=0 specchannelmax=20479 \
   expression="(FLAG==0) && (PATTERN<=4) && ((X,Y) IN ${pnbkg})"

backscale spectrumset=pn-source.pi badpixlocation=pn-filt.ev
backscale spectrumset=pn-background.pi badpixlocation=pn-filt.ev

rmfgen spectrumset=pn-source.pi rmfset=pn.rmf

arfgen spectrumset=pn-source.pi arfset=pn.arf withrmfset=yes rmfset=pn.rmf badpixlocation=pn-filt.ev detmaptype=psf

grppha 'pn-source.pi' 'pn_Grp.pi' comm="group min 20 & chkey BACKFILE pn-background.pi & chkey RESPFILE pn.rmf & chkey ANCRFILE pn.arf & exit" clobber=yes

read
read


cat << EOF
**********************************************************
EPIC MOS PIPELINE in $obsid/epic/mos
**********************************************************
EOF

cd $mypath/pps/$obsid/epic/mos
emproc >& emproc.log
#m1 event list 
M1evfile=`ls  -1 *EMOS1*ImagingEvts*`
echo $M1evfile
#m2 event list
M2evfile=`ls  -1 *EMOS2*ImagingEvts*`
echo $M2evfile

cat << EOF
**********************************************************
Images in 5 energy bands
**********************************************************
EOF

#extract single event (i.e. pattern zero only), high energy (E > 10 keV) light curves, to identify intervals of flaring particle background
evselect table=$M1evfile:EVENTS expression='#XMMEA_EM&&(PI>10000)&&(PATTERN==0)' \
  rateset="m1_back_lightc.fits" \
  timebinsize=10 withrateset=yes maketimecolumn=yes makeratecolumn=yes 2>&1

evselect table=$M2evfile:EVENTS expression='#XMMEA_EM&&(PI>10000)&&(PATTERN==0)' \
  rateset="m2_back_lightc.fits" \
  timebinsize=10 withrateset=yes maketimecolumn=yes makeratecolumn=yes 2>&1


 
#plot the light curves to decide about the cut to be applied for rejection of flaring periods
dsplot table=m1_back_lightc.fits x=TIME y=RATE   2>&1 &

threshold2=0.35
echo "Type a Low background threshold or press ENTER to use the default recommended value for MOS (0.35 [cts/s])" >&2
read newthreshold2
[ -n "$newthreshold2" ] && threshold2=$newthreshold2

#establish Good Time Intervals (GTIs) for every camera, since exposure coverage can be different
tabgtigen table=m1_back_lightc.fits expression="RATE.le.${threshold2}" gtiset=m1_back_gti.fits 2>&1

dsplot table=m2_back_lightc.fits x=TIME y=RATE   2>&1 &

threshold3=0.35
echo "Type a Low background threshold or press ENTER to use the default recommended value for MOS (0.35 [cts/s])" >&2
read newthreshold3
[ -n "$newthreshold3" ] && threshold3=$newthreshold3

#establish Good Time Intervals (GTIs) for every camera, since exposure coverage can be different
tabgtigen table=m2_back_lightc.fits expression="RATE.le.${threshold3}" gtiset=m2_back_gti.fits 2>&1


cat << EOF
**********************************************************
EPIC source finding
**********************************************************
EOF


#Produce images for MOS1 in 5 energy bands and from the whole spectral coverage
evselect table=$M1evfile:EVENTS imagebinning='binSize' imageset='m1_image_full.fits' \
  withimageset=yes xcolumn='X' ycolumn='Y' ximagebinsize=40 yimagebinsize=40 \
  expression='#XMMEA_EM&&(PI in [200:12000])&&(PATTERN in [0:12])&&(FLAG==0) && gti(m1_back_gti.fits,TIME)'

evselect table=$M1evfile:EVENTS  imagebinning='binSize' imageset='m1_image_b1.fits' \
  withimageset=yes xcolumn='X' ycolumn='Y' ximagebinsize=40 yimagebinsize=40 \
  expression='#XMMEA_EM&&(PI in [200:500])&&(PATTERN in [0:12])&&(FLAG==0) && gti(m1_back_gti.fits,TIME)'

evselect table=$M1evfile:EVENTS  imagebinning='binSize' imageset='m1_image_b2.fits' \
  withimageset=yes xcolumn='X' ycolumn='Y' ximagebinsize=40 yimagebinsize=40 \
  expression='#XMMEA_EM&&(PI in [500:1000])&&(PATTERN in [0:12])&&(FLAG==0) && gti(m1_back_gti.fits,TIME)'

evselect table=$M1evfile:EVENTS  imagebinning='binSize' imageset='m1_image_b3.fits' \
  withimageset=yes xcolumn='X' ycolumn='Y' ximagebinsize=40 yimagebinsize=40 \
  expression='#XMMEA_EM&&(PI in [1000:2000])&&(PATTERN in [0:12])&&(FLAG==0) && gti(m1_back_gti.fits,TIME)'

evselect table=$M1evfile:EVENTS  imagebinning='binSize' imageset='m1_image_b4.fits' \
  withimageset=yes xcolumn='X' ycolumn='Y' ximagebinsize=40 yimagebinsize=40 \
  expression='#XMMEA_EM&&(PI in [2000:4500])&&(PATTERN in [0:12])&&(FLAG==0) && gti(m1_back_gti.fits,TIME)'

evselect table=$M1evfile:EVENTS  imagebinning='binSize' imageset='m1_image_b5.fits' \
  withimageset=yes xcolumn='X' ycolumn='Y' ximagebinsize=40 yimagebinsize=40 \
  expression='#XMMEA_EM&&(PI in [4500:12000])&&(PATTERN in [0:12])&&(FLAG==0) && gti(m1_back_gti.fits,TIME)' 


#Produce images for MOS2 in 5 energy bands and from the whole spectral coverage

evselect table=$M2evfile:EVENTS imagebinning='binSize' imageset='m2_image_full.fits' \
  withimageset=yes xcolumn='X' ycolumn='Y' ximagebinsize=40 yimagebinsize=40 \
  expression='#XMMEA_EM&&(PI in [200:12000])&&(PATTERN in [0:12])&&(FLAG==0) && gti(m2_back_gti.fits,TIME)'

evselect table=$M2evfile:EVENTS  imagebinning='binSize' imageset='m2_image_b1.fits' \
  withimageset=yes xcolumn='X' ycolumn='Y' ximagebinsize=40 yimagebinsize=40 \
  expression='#XMMEA_EM&&(PI in [200:500])&&(PATTERN in [0:12])&&(FLAG==0) && gti(m2_back_gti.fits,TIME)'

evselect table=$M2evfile:EVENTS  imagebinning='binSize' imageset='m2_image_b2.fits' \
  withimageset=yes xcolumn='X' ycolumn='Y' ximagebinsize=40 yimagebinsize=40 \
  expression='#XMMEA_EM&&(PI in [500:1000])&&(PATTERN in [0:12])&&(FLAG==0) && gti(m2_back_gti.fits,TIME)'

evselect table=$M2evfile:EVENTS  imagebinning='binSize' imageset='m2_image_b3.fits' \
  withimageset=yes xcolumn='X' ycolumn='Y' ximagebinsize=40 yimagebinsize=40 \
  expression='#XMMEA_EM&&(PI in [1000:2000])&&(PATTERN in [0:12])&&(FLAG==0) && gti(m2_back_gti.fits,TIME)'

evselect table=$M2evfile:EVENTS  imagebinning='binSize' imageset='m2_image_b4.fits' \
  withimageset=yes xcolumn='X' ycolumn='Y' ximagebinsize=40 yimagebinsize=40 \
  expression='#XMMEA_EM&&(PI in [2000:4500])&&(PATTERN in [0:12])&&(FLAG==0) && gti(m2_back_gti.fits,TIME)'

evselect table=$M2evfile:EVENTS  imagebinning='binSize' imageset='m2_image_b5.fits' \
  withimageset=yes xcolumn='X' ycolumn='Y' ximagebinsize=40 yimagebinsize=40 \
  expression='#XMMEA_EM&&(PI in [4500:12000])&&(PATTERN in [0:12])&&(FLAG==0) && gti(m2_back_gti.fits,TIME)' 


#Run detection chains for all 

edetect_chain imagesets='"m1_image_b1.fits" "m1_image_b2.fits" "m1_image_b3.fits" "m1_image_b4.fits" "m1_image_b5.fits"' \
  eventsets=$M1evfile attitudeset=`ls  -1 *AttHk.ds*` \
  pimin='200 500 1000 2000 4500' pimax='500 1000 2000 4500 12000' \
  ecf='1.772 1.977 0.745 0.277 0.030' \
  eboxl_list='m1_eboxlist_l.fits' eboxm_list='m1_eboxlist_m.fits' \
  esp_nsplinenodes=16 eml_list='m1_emllist.fits' esen_mlmin=15

edetect_chain imagesets='"m2_image_b1.fits" "m2_image_b2.fits" "m2_image_b3.fits" "m2_image_b4.fits" "m2_image_b5.fits"' \
  eventsets=$M2evfile attitudeset=`ls  -1 *AttHk.ds*` \
  pimin='200 500 1000 2000 4500' pimax='500 1000 2000 4500 12000' \
  ecf='0.994 1.620 0.706 0.273 0.030' \
  eboxl_list='m2_eboxlist_l.fits' eboxm_list='m2_eboxlist_m.fits' \
  esp_nsplinenodes=16 eml_list='m2_emllist.fits' esen_mlmin=15

#Display the detected source on top the full energy bandpass image

srcdisplay boxlistset=m1_emllist.fits imageset=m1_image_full.fits sourceradius=0.01 &
srcdisplay boxlistset=m2_emllist.fits imageset=m2_image_full.fits sourceradius=0.01 &


cat << EOF
**********************************************************
Check MOS background for flaring
**********************************************************
EOF


evselect table=$M1evfile:EVENTS withrateset=yes \
	rateset=m1-flare.ra timecolumn=TIME \
	makeratecolumn=yes timebinsize=100 maketimecolumn=yes \
	filtertype=expression \
	expression='#XMMEA_EM && (PI>10000) && (PATTERN==0)'  2>&1

    AGAIN="y"
    until [ $AGAIN = "n" ] ;   do       # begin repeat background threshold

fplot table=m1-flare.ra TIME RATE[ERROR] - /xs - 

echo "How do you want to select Good Time Intervals? Type TIME or RATE:"
read gti_m1

if [ $gti_m1 = "RATE" ]; then
  thresholdm1=0.35
  echo "Type a Low background threshold or press ENTER to use the default recommended value for MOS (0.35 [cts/s])" 
  read newthresholdm1
  [ -n "$newthresholdm1" ] && thresholdm1=$newthresholdm1
  tabgtigen table=m1-flare.ra expression="RATE.le.${thresholdm1}" gtiset=m1-flare.gti 2>&1
else
  if [ $gti_m1 = "TIME" ]; then
    echo "Type the TIME value where the low-background begins:"
    read time_thresm1
    tabgtigen table=m1-flare.ra gtiset=m1-flare.gti expression="TIME.ge.${time_thresm1}" timecolumn=TIME 2>&1
    fi
fi   


cat << EOF
**********************************************************
Filtering data with selected gti
**********************************************************
EOF

evselect table=$M1evfile:EVENTS \
	    expression="#XMMEA_EM && (PI in [100:15000]) && gti(m1-flare.gti,TIME)" \
	    withfilteredset=yes filteredset=m1-filt.ev \
	    filtertype=expression keepfilteroutput=yes         2>&1

evselect table=m1-filt.ev:EVENTS withrateset=yes \
	rateset=m1-flare_after_gti.ra timecolumn=TIME \
	makeratecolumn=yes timebinsize=100 maketimecolumn=yes \
	filtertype=expression \
	expression='#XMMEA_EM && (PI>10000) && (PATTERN==0)'  2>&1

## Display the light curve 
dsplot table=m1-flare_after_gti.ra x=TIME y=RATE   2>&1 &

echo "Try new background threshold? (y/n)" >&2
read AGAIN

# end repeat background threshold
done

evselect table=$M2evfile:EVENTS withrateset=yes \
	rateset=m2-flare.ra timecolumn=TIME \
	makeratecolumn=yes timebinsize=100 maketimecolumn=yes \
	filtertype=expression \
	expression='#XMMEA_EM && (PI>10000) && (PATTERN==0)'  2>&1

    AGAIN="y"
    until [ $AGAIN = "n" ] ;   do       # begin repeat background threshold

fplot table=m2-flare.ra TIME RATE[ERROR] - /xs - 

echo "How do you want to select Good Time Intervals? Type TIME or RATE:"
read gti_m2

if [ $gti_m2 = "RATE" ]; then
  thresholdm2=0.35
  echo "Type a Low background threshold or press ENTER to use the default recommended value for MOS (0.35 [cts/s])" 
  read newthresholdm2
  [ -n "$newthresholdm2" ] && thresholdm2=$newthresholdm2
  tabgtigen table=m2-flare.ra expression="RATE.le.${thresholdm2}" gtiset=m2-flare.gti 2>&1
else
  if [ $gti_m2 = "TIME" ]; then
    echo "Type the TIME value where the low-background begins:"
    read time_thresm2
    tabgtigen table=m2-flare.ra gtiset=m2-flare.gti expression="TIME.ge.${time_thresm2}" timecolumn=TIME 2>&1
    fi
fi   
dsplot table=m2-flare.ra x=TIME y=RATE   2>&1 &
echo "MOS2: Low background threshold? (recommended: 0.35 [cts/s])" >&2
read thresholdm2

tabgtigen table=m2-flare.ra expression="RATE.le.${thresholdm2}" gtiset=m2-flare.gti     2>&1

cat << EOF
**********************************************************
Filtering data with selected gti
**********************************************************
EOF

evselect table=$M2evfile:EVENTS \
	    expression="#XMMEA_EM && (PI in [100:15000]) && gti(m2-flare.gti,TIME)" \
	    withfilteredset=yes filteredset=m2-filt.ev \
	    filtertype=expression keepfilteroutput=yes         2>&1

evselect table=m2-filt.ev:EVENTS withrateset=yes \
	rateset=m2-flare_after_gti.ra timecolumn=TIME \
	makeratecolumn=yes timebinsize=100 maketimecolumn=yes \
	filtertype=expression \
	expression='#XMMEA_EM && (PI>10000) && (PATTERN==0)'  2>&1

## Display the light curve 
dsplot table=m2-flare_after_gti.ra x=TIME y=RATE   2>&1 &

echo "Try new background threshold? (y/n)" >&2
read AGAIN

# end repeat background threshold
done

cat << EOF
**********************************************************
Create a sky image of the filtered data set
**********************************************************
EOF


evselect table=m1-filt.ev:EVENTS withimageset=yes \
	      imageset=m1-filt.im xcolumn=X ycolumn=Y \
	      imagebinning=binSize ximagebinsize=80 yimagebinsize=80      2>&1

ds9 -cmap bb -scale sqrt -geometry 650x850 \
		  m1-filt.im 	  2>&1 &

cat << EOF
**********************************************************
Extraction of SPECTRUM and LIGHT CURVE
**********************************************************
EOF

echo "Select MOS1 source and background regions in ds9, save the regions as "m1-source.reg" and "m1-back.reg" in ds9 Physical mode and press ENTER"

read

m1src=`cat m1-source.reg | tail -n 1`
m1bkg=`cat m1-back.reg | tail -n 1`


eregionanalyse imageset=m1-filt.im srcexp="(X,Y) IN $m1src" backexp="(X,Y) IN $m1bkg" | tee eregionanalyse_m1.log

m1nsrcX=`cat eregionanalyse_m1.log | grep SASCIRCLE | tr -d 'SASCIRCLE: in CIRCLE X Y ()' | awk -F ',' '{ print $2 }'`
m1nsrcY=`cat eregionanalyse_m1.log | grep SASCIRCLE | tr -d 'SASCIRCLE: in CIRCLE X Y ()' | awk -F ',' '{ print $3 }'`
m1nsrcrad=`cat eregionanalyse_m1.log | grep SASCIRCLE | tr -d 'SASCIRCLE: in CIRCLE X Y ()' | awk -F ',' '{ print $4 }'`

echo "You have selected the following source region: $m1src \
eregionanalyse suggests to use ($m1nsrcX,$m1nsrcY,$m1nsrcrad) as optimal coordinates for source extraction. Do you want to use the suggested coordinates? (y/n)" >&2
read ANSWERm1


if [ $ANSWERm1 = "y" ]; then
      m1src="circle($m1nsrcX,$m1nsrcY,$m1nsrcrad)"
      echo "New source: $m1src. Do you want to change the background radius? (It's recommended to select a radius which is at least 2 x source radius) (y/n)"
      read ans2m1
      if [ $ans2m1 = "y" ]; then
	  ds9 m1-filt.im -cmap bb -scale sqrt -geometry 650x850 -region m1-back.reg	 2>&1 &
	  echo "Select a new background region in ds9, save the region as "m1-back-2.reg" in ds9 Physical mode and press ENTER"
	  read
	  m1bkg=`cat m1-back-2.reg | tail -n 1`
      fi
else
    if [ $ANSWERm1 = "n" ]; then
      m1src=$m1src
    fi
fi

echo "Source will be extracted in $m1src and background: $m1bkg"


evselect table=m2-filt.ev:EVENTS withimageset=yes \
	      imageset=m2-filt.im xcolumn=X ycolumn=Y \
	      imagebinning=binSize ximagebinsize=80 yimagebinsize=80      2>&1

ds9 -cmap bb -scale sqrt -geometry 650x850 \
		  m2-filt.im 	  2>&1 &



echo "Select MOS2 source and background regions in ds9, save the regions as "m2-source.reg" and "m2-back.reg" in ds9 Physical mode and press ENTER"

read

m2src=`cat m2-source.reg | tail -n 1`
m2bkg=`cat m2-back.reg | tail -n 1`


eregionanalyse imageset=m2-filt.im srcexp="(X,Y) IN $m2src" backexp="(X,Y) IN $m2bkg" | tee eregionanalyse_m2.log

m2nsrcX=`cat eregionanalyse_m2.log | grep SASCIRCLE | tr -d 'SASCIRCLE: in CIRCLE X Y ()' | awk -F ',' '{ print $2 }'`
m2nsrcY=`cat eregionanalyse_m2.log | grep SASCIRCLE | tr -d 'SASCIRCLE: in CIRCLE X Y ()' | awk -F ',' '{ print $3 }'`
m2nsrcrad=`cat eregionanalyse_m2.log | grep SASCIRCLE | tr -d 'SASCIRCLE: in CIRCLE X Y ()' | awk -F ',' '{ print $4 }'`

echo "You have selected the following source region: $m2src \
eregionanalyse suggests to use ($m2nsrcX,$m2nsrcY,$m2nsrcrad) as optimal coordinates for source extraction. Do you want to use the suggested coordinates? (y/n)" >&2
read ANSWERm2

if [ $ANSWERm2 = "y" ]; then
      m2src="circle($m2nsrcX,$m2nsrcY,$m2nsrcrad)"
      echo "New source: $m2src. Do you want to change the background radius? (It's recommended to select a radius which is at least 2 x source radius) (y/n)"
      read ans2m2
      if [ $ans2m2 = "y" ]; then
	  ds9 m2-filt.im -cmap bb -scale sqrt -geometry 650x850 -region m2-back.reg	 2>&1 &
	  echo "Select a new background region in ds9, save the region as "m2-back-2.reg" in ds9 Physical mode and press ENTER"
	  read
	  m2bkg=`cat m2-back-2.reg | tail -n 1`
      fi
else
    if [ $ANSWERm2 = "n" ]; then
      m2src=$m2src
    fi
fi

echo "Source will be extracted in $m2src and background: $m2bkg"

cp m1-filt.ev $mypath/pps/$obsid/timing
cp m1-filt.ev $mypath/pps/$obsid/spectra
cp m2-filt.ev $mypath/pps/$obsid/timing
cp m2-filt.ev $mypath/pps/$obsid/spectra


cat << EOF
**********************************************************
Creating MOS light curve in $mypath/pps/$obsid/timing
**********************************************************
EOF

cd $mypath/pps/$obsid/timing

barycen table=m1-filt.ev:EVENTS

   tbAGAINm1="y"
   until [ $tbAGAINm1 = "n" ] ;   do       # begin repeat background threshold

ntb_m1=100
echo "Choose a time bin size for MOS1 light curve or press ENTER to use the default value (100 s):"
read newntb_m1
[ -n "$newntb_m1" ] && ntb_m1=$newntb_m1

evselect table=m1-filt.ev energycolumn=PI expression="#XMMEA_EM && (PATTERN<=12) && ((X,Y) IN ${m1src}) && (PI in [200:10000])" \
    withrateset=yes rateset="m1_source_lightcurve_raw.lc" timebinsize=${ntb_m1} \
    maketimecolumn=yes makeratecolumn=yes 

evselect table=m1-filt.ev energycolumn=PI expression="#XMMEA_EM && (PATTERN<=12) && ((X,Y) IN ${m1bkg}) && (PI in [200:10000])" withrateset=yes \
   rateset="m1_back_lightcurve_raw.lc" timebinsize=${ntb_m1} \
   maketimecolumn=yes makeratecolumn=yes 

epiclccorr srctslist=m1_source_lightcurve_raw.lc eventlist=m1-filt.ev outset=m1${ntb_m1}-lccorr.lc bkgtslist=m1_back_lightcurve_raw.lc withbkgset=yes applyabsolutecorrections=yes

dsplot table=m1${ntb_m1}-lccorr.lc withx=yes x=TIME withy=yes y=RATE &

echo "Try new time bin size? (y/n)" >&2
read tbAGAINm1

# end repeat 
done

barycen table=m2-filt.ev:EVENTS

   tbAGAINm2="y"
   until [ $tbAGAINm2 = "n" ] ;   do       # begin repeat background threshold

ntb_m2=100
echo "Choose a time bin size for MOS1 light curve or press ENTER to use the default value (100 s):"
read newntb_m2
[ -n "$newntb_m2" ] && ntb_m2=$newntb_m2

evselect table=m2-filt.ev energycolumn=PI expression="#XMMEA_EM && (PATTERN<=12) && ((X,Y) IN ${m2src}) && (PI in [200:10000])" \
    withrateset=yes rateset="m2_source_lightcurve_raw.lc" timebinsize=${ntb_m2} \
    maketimecolumn=yes makeratecolumn=yes 

evselect table=m2-filt.ev energycolumn=PI expression="#XMMEA_EM && (PATTERN<=12) && ((X,Y) IN ${m2bkg}) && (PI in [200:10000])" withrateset=yes \
   rateset="m2_back_lightcurve_raw.lc" timebinsize=${ntb_m2} \
   maketimecolumn=yes makeratecolumn=yes 

epiclccorr srctslist=m2_source_lightcurve_raw.lc eventlist=m2-filt.ev outset=m2${ntb_m2}-lccorr.lc bkgtslist=m2_back_lightcurve_raw.lc withbkgset=yes applyabsolutecorrections=yes

dsplot table=m2${ntb_m2}-lccorr.lc withx=yes x=TIME withy=yes y=RATE &

echo "Try new time bin size? (y/n)" >&2
read tbAGAINm2

# end repeat 
done

cat << EOF
**********************************************************
Creating MOS spectra in $mypath/pps/$obsid/spectra
**********************************************************
EOF

cd $mypath/pps/$obsid/spectra

evselect table=m1-filt.ev withspectrumset=yes spectrumset=m1-source.pi \
  energycolumn=PI spectralbinsize=5 withspecranges=yes specchannelmin=0 specchannelmax=11999 \
  expression="#XMMEA_EM && (PATTERN<=12) && ((X,Y) IN ${m1src})"


evselect table=m1-filt.ev withspectrumset=yes spectrumset=m1-background.pi \
   energycolumn=PI spectralbinsize=5 withspecranges=yes specchannelmin=0 specchannelmax=11999 \
   expression="#XMMEA_EM && (PATTERN<=12) && ((X,Y) IN ${m1bkg})"

backscale spectrumset=m1-source.pi badpixlocation=m1-filt.ev
backscale spectrumset=m1-background.pi badpixlocation=m1-filt.ev

rmfgen spectrumset=m1-source.pi rmfset=m1.rmf

arfgen spectrumset=m1-source.pi arfset=m1.arf withrmfset=yes rmfset=m1.rmf badpixlocation=m1-filt.ev detmaptype=psf

grppha 'm1-source.pi' 'm1_Grp.pi' comm="group min 20 & chkey BACKFILE m1-background.pi & chkey RESPFILE m1.rmf & chkey ANCRFILE m1.arf & exit" clobber=yes



evselect table=m2-filt.ev withspectrumset=yes spectrumset=m2-source.pi \
  energycolumn=PI spectralbinsize=5 withspecranges=yes specchannelmin=0 specchannelmax=11999 \
  expression="#XMMEA_EM && (PATTERN<=12) && ((X,Y) IN ${m2src})"


evselect table=m2-filt.ev withspectrumset=yes spectrumset=m2-background.pi \
   energycolumn=PI spectralbinsize=5 withspecranges=yes specchannelmin=0 specchannelmax=11999 \
   expression="#XMMEA_EM && (PATTERN<=12) && ((X,Y) IN ${m2bkg})"

backscale spectrumset=m2-source.pi badpixlocation=m2-filt.ev
backscale spectrumset=m2-background.pi badpixlocation=m2-filt.ev

rmfgen spectrumset=m2-source.pi rmfset=m2.rmf

arfgen spectrumset=m2-source.pi arfset=m2.arf withrmfset=yes rmfset=m2.rmf badpixlocation=m2-filt.ev detmaptype=psf

grppha 'm2-source.pi' 'm2_Grp.pi' comm="group min 20 & chkey BACKFILE m2-background.pi & chkey RESPFILE m2.rmf & chkey ANCRFILE m2.arf & exit" clobber=yes


cat << EOF
**********************************************************
RGS pipeline in $mypath/pps/$obsid/rgs
**********************************************************
EOF

cd $mypath/pps/$obsid/rgs

rgsproc # -V 5 >& rgsproc.log 

r1srcli=`ls -t P*R1*SRCLI_0000.FIT`

fv $r1srcli & 
echo "Check that the coordinates of the PROPOSAL source are correct" >&2
read 

r1ev=`ls -t P*R1*EVENLI0000.FIT`

evselect table=$r1ev:EVENTS \
  imageset='r1_spatial.fit' xcolumn='BETA_CORR' ycolumn='XDSP_CORR'

evselect table=$r1ev:EVENTS \
  imageset='r1_pi.fit' xcolumn='BETA_CORR' ycolumn='PI'\
  yimagemin=0 yimagemax=3000 \
  expression="REGION(${r1srcli}:RGS1_SRC1_SPATIAL,BETA_CORR,XDSP_CORR)"

rgsimplot endispset='r1_pi.fit' spatialset='r1_spatial.fit' \
  srcidlist='1' srclistset="${r1srcli}" \
  device=/xs

cat << EOF
**********************************************************
Check RGS1 background for flaring
**********************************************************
EOF

evselect table=$r1ev timebinsize=100 \
  rateset=r1_background_lc.fit \
  makeratecolumn=yes maketimecolumn=yes \
  expression="(CCDNR==9)&&(REGION(${r1srcli}:RGS1_BACKGROUND,BETA_CORR,XDSP_CORR))"

dsplot table=r1_background_lc.fit x=TIME y=RATE &

echo "Is it necessary to create a Good Time Interval table? (y/n)"
read r1flare

if [ $r1flare = "y" ]; then
      echo "RGS1: Low background threshold? (typically from 0.1 to 2 cts/s)" >&2
      read threshold_r1
      tabgtigen table=r1_background_lc.fit gtiset=r1_gti.fit expression="(RATE < ${threshold_r1})"  2>&1
      r1merged=`ls -t  P*R1*merged0000.FIT`
      cp $r1ev $r1merged
      rgsproc entrystage=3:filter auxgtitables=r1_gti.fit 
else
    if [ $r1flare = "n" ]; then
      r1ev=$r1ev
    fi
fi

cat << EOF
*************************************************************
Extracting RGS1 1st order spectrum in $mypath/pps/$obsid/rgs
*************************************************************
EOF


cp P*R1*SRSPEC1*.FIT r1-source.pi
cp P*R1*BGSPEC1*.FIT r1-back.pi
cp P*R1*RSPMAT1*.FIT r1-rmf.rmf

grppha 'r1-source.pi' 'r1_Grp.pi' comm="group min 20 & chkey BACKFILE r1-back.pi & chkey RESPFILE r1-rmf.rmf & exit" clobber=yes

r2srcli=`ls -t P*R2*SRCLI_0000.FIT`

fv $r2srcli & 
echo "Check that the coordinates of the PROPOSAL source are correct" >&2
read 

r2ev=`ls -t P*R2*EVENLI0000.FIT`

evselect table=$r2ev:EVENTS \
  imageset='r2_spatial.fit' xcolumn='BETA_CORR' ycolumn='XDSP_CORR'

evselect table=$r2ev:EVENTS \
  imageset='r2_pi.fit' xcolumn='BETA_CORR' ycolumn='PI'\
  yimagemin=0 yimagemax=3000 \
  expression="REGION(${r2srcli}:RGS2_SRC1_SPATIAL,BETA_CORR,XDSP_CORR)"

rgsimplot endispset='r2_pi.fit' spatialset='r2_spatial.fit' \
  srcidlist='1' srclistset="${r2srcli}" \
  device=/xs

cat << EOF
**********************************************************
Check RGS2 background for flaring
**********************************************************
EOF

evselect table=$r2ev timebinsize=100 \
  rateset=r2_background_lc.fit \
  makeratecolumn=yes maketimecolumn=yes \
  expression="(CCDNR==9)&&(REGION(${r2srcli}:RGS2_BACKGROUND,BETA_CORR,XDSP_CORR))"

dsplot table=r2_background_lc.fit x=TIME y=RATE &

echo "Is it necessary to create a Good Time Interval table? (y/n)"
read r2flare

if [ $r2flare = "y" ]; then
      echo "RGS2: Low background threshold? (typically from 0.1 to 2 cts/s)" >&2
      read threshold_r2
      tabgtigen table=r2_background_lc.fit gtiset=r2_gti.fit expression="(RATE < ${threshold_r2})"  2>&1
      r2merged=`ls -t  P*R2*merged0000.FIT`
      cp $r2ev $r2merged
      rgsproc entrystage=3:filter auxgtitables=r2_gti.fit 
else
    if [ $r2flare = "n" ]; then
      r2ev=$r2ev
    fi
fi

cat << EOF
*************************************************************
Extracting RGS2 1st order spectrum in $mypath/pps/$obsid/rgs
*************************************************************
EOF


cp P*R2*SRSPEC1*.FIT r2-source.pi
cp P*R2*BGSPEC1*.FIT r2-back.pi
cp P*R2*RSPMAT1*.FIT r2-rmf.rmf

grppha 'r2-source.pi' 'r2_Grp.pi' comm="group min 20 & chkey BACKFILE r2-back.pi & chkey RESPFILE r2-rmf.rmf & exit" clobber=yes

cat << EOF
**********************************************************
OM pipeline in $mypath/pps/$obsid/om
**********************************************************
EOF

cd $mypath/pps/$obsid/om/image

#omichain  >& omichain.log

cd $mypath/pps/$obsid/om/timing

for omlightcurve in `ls -t *P*TIMESR1000*.FIT`;
do

  tb_omAGAIN="y"
     until [ $tb_omAGAIN = "n" ] ;   do       

      ntb_om=10
      echo "Choose a time bin size for the OM light curve or press ENTER to use the default value (10 s)"
      read newntb_om
      [ -n "$newntb_om" ] && ntb_om=$newntb_om
    
      omfchain timebinsize=$ntb_om #>& omfchain.log
      fplot $omlightcurve TIME RATE - /xs q

      echo "Try new time bin size? (y/n)" >&2
      read tb_omAGAIN

     done

echo "$omlightcurve observed with filter:"
ftkeypar $omlightcurve filter chatter=3 | grep value | tr -d "value: ' " 

done

mergeAGAIN="y"
   until [ $mergeAGAIN = "n" ] ;   do

PS3="Now you have to merge light curves with the same filters. Select 2 light curves to be merged: "
#all_choices=""
select choice in `ls -t *P*TIMESR1000*.FIT`;
do
    if [ -n "$choice" ]; then
	echo "you selected $choice [$REPLY]"
    fi
	break;
  done

echo "Enter a name for the merged light curve:"
read merged_name
fmerge "$REPLY" $merged_name
cp $merged_name $mypath/pps/$obsid/timing
echo "Are there more light curves to be merged? (y/n)" >&2
read mergeAGAIN


done


cat << EOF
**********************************************************
Light curve folding in $mypath/pps/$obsid/timing
**********************************************************
EOF

cd $mypath/pps/$obsid/timing