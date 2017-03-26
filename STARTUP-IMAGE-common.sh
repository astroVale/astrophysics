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


if [ $1 ] ;
then 
    mypath=$1 
else 
    echo "Usage: $0 <insert working_directory>"; 
    exit 0
fi


source $HEADAS/headas-init.sh

source $SAS/setsas.sh
export SAS_CCFPATH=/net/konraid/xray/xraysoft/xmmsas/ccf/

sasversion

cd $mypath/obs
#--------------------------------------------------------------------------
#                               LOOP
#--------------------------------------------------------------------------

echo "extracting archive"

for archive in *.tar ;
do

obsid=`tar -tf $archive | head -n 2 | tail -n 1 | tr -d '/.' `

#----------------------------------------------------------------------------
#                             2- prepare the raw data odf
#----------------------------------------------------------------------------

#uncompress the files
tar -xvf *.tar

echo "directory " $obsid

cd $obsid/odf
gunzip *.gz
tar -xvf *.tar
tar -xvf *.TAR
rm *.tar
rm *.TAR

echo "Setting ODF and CCF"

#point to an ODF
odfpath=`pwd`
export SAS_ODF=$odfpath
echo $SAS_ODF

#----------------------------------------------------------------------------
#                             3- make the CCF and ODF summary file
#----------------------------------------------------------------------------

echo "generating and pointing to a Calibration Index File (CIF)"
#rm ccf.cif
cifbuild
export SAS_CCF=$odfpath/ccf.cif
echo $SAS_CCF

echo "prepare the data and produce the summary file"

#rm *SUM.SAS
odfingest
sumfile=`ls -t *SUM.SAS | head -1`
export SAS_ODF=$odfpath/$sumfile
echo $SAS_ODF

#-------------------------------------------------------------------------
#                             4- rerun the pipeline
#------------------------------------------------------------------------

#produce calibrated photon event files for PN and MOS.
#run the pipeline processing

echo "running the pipeline"
#create a result directory for each detid

cd $mypath
mkdir -p pps/$obsid/epic
cd pps/$obsid/epic
export ppspath=$PWD
echo $ppspath
mkdir pn
cd pn

epproc

#cd $ppspath
#mkdir mos
#cd mos
#emproc


#define the name of the input calibrated event list as a variable
#pn event list 
PNevfile=$ppspath/pn/`ls  -1 *EPN*ImagingEvts*`
echo $PNevfile
#m1 event list 
#M1evfile=$ppspath/mos/`ls  -1 *EMOS1*ImagingEvts*`
#echo $M1evfile
#m2 event list
#M2evfile = $ppspath/mos/`ls  -1 *EMOS2*ImagingEvts*`
#echo $M2evfile



#------------------------------------------------------------------------------
#                             5- create the light curve
#------------------------------------------------------------------------------
#                             PN light curve
#-----------------------------------------------------------------------------

cd $ppspath/pn
#Create a light-curve for the observation to check for flaring high background periods (pn)
evselect table=$PNevfile withrateset=yes rateset=PN-rates.fits timecolumn=TIME timebinsize=100 maketimecolumn=yes makeratecolumn=yes expression='#XMMEA_EP && PI in [10000:12000] && (PATTERN==0)'
#Plot the light-curve
dsplot table=PN-rates.fits x=TIME y=RATE &

#------------------------------------------------------------------------------
#                             MOS1 light curve
#------------------------------------------------------------------------------

#cd $ppspath/mos

#Create a light-curve for the observation to check for flaring high background periods (MOS1)
#evselect table=$M1evfile withrateset=yes rateset=M1-rates.fits timecolumn=TIME timebinsize=100 maketimecolumn=yes makeratecolumn=yes expression='#XMMEA_EM && PI > 10000 && (PATTERN==0)'
#Plot the light-curve
#dsplot table=M1-rates.fits x=TIME y=RATE &

#------------------------------------------------------------------------------
#                             MOS2 light curve
#------------------------------------------------------------------------------

#Create a light-curve for the observation to check for flaring high background periods (MOS2)
#evselect table=$M2evfile withrateset=yes rateset=M2-rates.fits timecolumn=TIME timebinsize=100 maketimecolumn=yes makeratecolumn=yes expression='#XMMEA_EM && PI > 10000 && (PATTERN==0)'
#Plot the light-curve
#dsplot table=M2-rates.fits x=TIME y=RATE &

#------------------------------------------------------------------------------
#                             6- filter the event file
#------------------------------------------------------------------------------
#                             PN filtered event file
#------------------------------------------------------------------------------

cd $ppspath/pn
#Determine a threshold on the light-curve, defining "low background" intervals (PN: 0.4 counts/s) and create a corresponding good time interval (GTI) file
tabgtigen table=PN-rates.fits expression='RATE<=0.4' gtiset=PN-gti.fits

#Create an event list which is free of high background periods.
evselect table=$PNevfile withfilteredset=Y filteredset=PN-filtered.fits keepfilteroutput=true destruct=Y expression='#XMMEA_EP && gti(PN-gti.fits,TIME) && (PI in [100:15000]) && (PATTERN<=4)'

#Create a new light curve to make sure that the flaring background time intervals were removed:
evselect table=PN-filtered.fits withrateset=yes rateset=PN-rates_new.fits timecolumn=TIME timebinsize=100 maketimecolumn=yes makeratecolumn=yes expression='#XMMEA_EP && PI in [10000:12000] && (PATTERN==0)' 

#Plot the new light-curve
dsplot table=PN-rates_new.fits x=TIME y=RATE &

#------------------------------------------------------------------------------
#                             MOS1 filtered event file
#------------------------------------------------------------------------------

#cd $ppspath/mos
#Determine a threshold on the light-curve, defining "low background" intervals (M1: 0.35 counts/s) and create a corresponding good time interval (GTI) file
#tabgtigen table=M1-rates.fits expression='RATE<=0.35' gtiset=M1-gti.fits

#Create an event list which is free of high background periods.
#evselect table=$M1evfile withfilteredset=true filteredset=M1-filtered.fits keepfilteroutput=true destruct=true expression='#XMMEA_EM && (gti(M1-gti.fits,TIME) && (PI in [100:15000]) && (PATTERN<=12))'


#Create a new light curve to make sure that the flaring background time intervals were removed:
#evselect table=M1-filtered.fits withrateset=yes rateset=M1-rates_new.fits timecolumn=TIME timebinsize=100 maketimecolumn=yes makeratecolumn=yes expression='#XMMEA_EM && PI > 10000 && (PATTERN==0)' 

#Plot the new light-curve
#dsplot table=M1-rates_new.fits x=TIME y=RATE &


#------------------------------------------------------------------------------
#                             MOS2 filtered event file
#-----------------------------------------------------------------------------

#Determine a threshold on the light-curve, defining "low background" intervals (M2: 0.35 counts/s) and create a corresponding good time interval (GTI) file
#tabgtigen table=M2-rates.fits expression='RATE<=0.35' gtiset=M2-gti.fits

#Create an event list which is free of high background periods.
#evselect table=$M2evfile withfilteredset=true filteredset=M2-filtered.fits keepfilteroutput=true destruct=true expression='(gti(M2-gti.fits,TIME) && (PI in [100:15000]) && (PATTERN<=12))'


#Create a new light curve to make sure that the flaring background time intervals were removed:
#evselect table=M2-filtered.fits withrateset=yes rateset=M2-rates_new.fits timecolumn=TIME timebinsize=100 maketimecolumn=yes makeratecolumn=yes expression='#XMMEA_EM && PI > 10000 && (PATTERN==0)' 

#Plot the new light-curve
#dsplot table=M2-rates_new.fits x=TIME y=RATE &


#------------------------------------------------------------------------------
#                             7- create the sky images of the filtered data
#                             8- select src and bdg regions
#------------------------------------------------------------------------------
#                             PN sky image & select src and bdg regions
#-----------------------------------------------------------------------------

#Create a sky image of the filtered data set
evselect table=PN-filtered.fits withimageset=true imageset=PN-image.fits xcolumn=X ycolumn=Y imagebinning=binSize ximagebinsize=80 yimagebinsize=80 expression='PI in [500:2000]'

#display the image with ds9:
#ds9 PN-image.fits -scale linear -scale mode 99.75  -cmap heat -zoom to fit -view colorbar no &
ds9 PN-image.fits &

#------------------------------------------------------------------------------
#                             MOS1 sky image & select src and bdg regions
#------------------------------------------------------------------------------

#Create a sky image of the filtered data set
#evselect table=M1-filtered.fits withimageset=true imageset=M1-image.fits xcolumn=X ycolumn=Y imagebinning=binSize ximagebinsize=80 yimagebinsize=80 expression='PI in [500:2000]'

#display the image with ds9:
#ds9 M1-image.fits -scale linear -scale mode 99.75  -cmap heat -zoom to fit -view colorbar no &


#---------------------------------------------------------------------------
#                             MOS2 sky image & select src and bdg regions
#--------------------------------------------------------------------------

#Create a sky image of the filtered data set
#evselect table=M2-filtered.fits withimageset=true imageset=M2-image.fits xcolumn=X ycolumn=Y imagebinning=binSize ximagebinsize=80 yimagebinsize=80 expression='PI in [500:2000]'

#display the image with ds9:
#ds9 M2-image.fits -scale linear -scale mode 99.75  -cmap heat -zoom to fit -view colorbar no &




done
