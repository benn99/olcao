module O_Intg

contains

subroutine intgPSCF

   ! Import the necessary modules.
   use O_Kinds
   use O_Constants
   use O_CommandLine
   use O_Lattice
   use O_Basis
   use O_Input
   use O_TimeStamps
   use O_Potential
   use O_PSCFIntgHDF5
   use O_IntegralsPSCF

   ! Make sure that there are not accidental variable declarations.
   implicit none

   type(commandLineParameters) :: clp ! from O_commandLine
   type(inputData) :: inDat ! from O_input

   ! Open the potential file that will be read from in this program.
   open (unit=8,file='fort.8',status='old',form='formatted')


   ! Initialize the logging labels.
   call initOperationLabels


   ! Parse the command line parameters
   call parseIntgCommandLine(clp)


   ! Read in the input to initialize all the key data structure variables.
   call parseInput(inDat,clp)


   ! Find specific computational parameters not EXPLICITLY given in the input
   !   file.  These values can, however, be easily determined from the input
   !   file.
   call getImplicitInfo


   ! Create real-space super lattice out of the primitive lattice.  These
   !   "supercells" must be big enough so as to include all the points within
   !   sphere bounded by the negligability limit.  Points outside the sphere
   !   are considered negligable and are ignored.
   call initializeLattice (1)


   ! Setup the necessary data structures so that we can easily find the lattice
   !   vector that is closest to any other arbitrary vector.
   call initializeFindVec


   ! Renormalize the basis functions
   call renormalizeBasis

!write (20,*) "Got here 0"
!call flush (20)

   ! Prepare the HDF5 files for the post SCF integrals.
   call initPSCFIntgHDF5

!write (20,*) "Got here 1"
!call flush (20)

   ! Read the provided potential coefficients.
   call initPotCoeffs

!write (20,*) "Got here 2"
!call flush (20)
   ! Compute the integrals and the momentum matrix elements (MME or MOME) (if
   !   requested).  The MME request is given on the command line and the
   !   subroutine gets that flag from that module.  The integrals are also
   !   optional and are controlled by the intgAndOrMom parameter.  Obviously,
   !   in this program the whole point is to compute the integrals.  However,
   !   in other programs (optc) the integrals do not need to be computed and
   !   only the MME need to be computed.  In that case the same subroutine can
   !   be used, except that only the MME are computed, not the overlap and
   !   hamiltonian.
   call intgAndOrMom(1,clp%doMOME)


   ! Record to the HDF5 file an attribute that says whether or not the MOME
   !   were computed.
   call setMOMEStatus(clp%doMOME)


   ! Close the HDF5 PSCF integrals file.
   call closePSCFIntgHDF5


   ! Open a file to signal completion of the program.
   open (unit=2,file='fort.2',status='new')

end subroutine intgPSCF


subroutine getImplicitInfo

   ! Import necessary modules.
   use O_AtomicSites
   use O_AtomicTypes
   use O_PotSites
   use O_PotTypes
   use O_Lattice
   use O_KPoints
   use O_Potential
   use O_TimeStamps

   implicit none

   call timeStampStart(2)

   call getAtomicTypeImplicitInfo
   call getAtomicSiteImplicitInfo
   call getPotSiteImplicitInfo
   call getPotTypeImplicitInfo

   ! Used to later obtain the inverse matrix of the real cell vectors.
   call getRecipCellVectors

   call initPotStructures

   call timeStampEnd(2)

end subroutine getImplicitInfo

end module O_Intg
