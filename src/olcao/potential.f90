module O_Potential

   ! Import necessary modules.
   use O_Kinds

   ! Make sure that no funny variables are defined.
   implicit none

   ! Define access
   public

   !!!!!!!!!!!!!!!!!!!!!!!!!!!!!
   ! Begin list of module data.!
   !!!!!!!!!!!!!!!!!!!!!!!!!!!!!

   ! Define variables for the solid state potential.
   integer :: numAlphas ! The total number of potential terms (alphas) in the
         !   system.
   integer :: potDim ! Total potential dimension determined as the sum number
         !   of alphas for all potential types.
   real (kind=double), allocatable, dimension (:)   :: potAlphas ! An ordered
         !   list of all the alphas of all types in the system.
   real (kind=double), allocatable, dimension (:)   :: intgConsts ! A list of
         !   constants of integration for the terms of each type in the system.
   real (kind=double), allocatable, dimension (:)   :: typeSpinSplit ! The
         !   initial splitting used for each type.  This will be applied to
         !   every term in potDim as the spinSplitFactor below.
   real (kind=double), allocatable, dimension (:)   :: spinSplitFactor ! A
         !   factor -1.0 to 1.0 for each potential alpha (term) that is used
         !   to create the initial spin splitting kick.  The number (x say) is
         !   used as follows:  (up-down) = (up+down)*x.
   real (kind=double), allocatable, dimension (:,:) :: potCoeffs ! An ordered
         !   list of the potential coefficients for each spin orientation.
         !   Index1=coeff; Index2=spin(1=up,2=dn)

   ! Define variables for controlling convergence of the potential.
   integer :: feedbackLevel
   integer :: lastIteration
   integer :: XC_CODE
   integer :: currIteration
   integer :: converged
   real (kind=double) :: relaxFactor
   real (kind=double) :: convgTest

   integer :: spin
   integer :: rel
   integer :: GGA

   !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
   ! Begin list of module subroutines.!
   !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
   contains


! Set up data structures and values associated with the total potential
!   function.
subroutine initPotStructures

   ! Use necessary modules.
   use O_Kinds
   use O_Constants
   use O_PotTypes

   implicit none

   ! Define local variables.
   integer :: i,j
   real (kind=double) :: pi32  ! pi^(3/2)

   ! Initialize variables
   pi32            = pi ** 1.5_double
   potDim          = 0

   ! Compute the value for potDim.
   potDim = potTypes(numPotTypes)%cumulAlphaSum+potTypes(numPotTypes)%numAlphas

   ! Allocate space for the spin split factor, integration constants, and
   !   actual alphas in one long ordered list.
   allocate (spinSplitFactor (potDim))
   allocate (intgConsts      (potDim))
   allocate (potAlphas       (potDim))

   ! Compute the constants of integration, copy the potential alphas into the
   !   total list from the individual types, and copy the spin split factor
   !   from each type to all terms of that type.
   do i = 1, numPotTypes

      ! Calculate the integration constants where the constant (j) is the
      !   multiplicity * (pi^(3/2)) / alpha(j) * alpha(j)^1/2.
      ! Also store the alphas of all the types in one array.
      do j = 1, potTypes(i)%numAlphas

         spinSplitFactor(j + potTypes(i)%cumulAlphaSum) = typeSpinSplit(i)

         potAlphas(j + potTypes(i)%cumulAlphaSum) = potTypes(i)%alphas(j)

         intgConsts(j + potTypes(i)%cumulAlphaSum) = &
               & real(potTypes(i)%multiplicity,double) * &
               & pi32 / (potTypes(i)%alphas(j))**(3.0_double/2.0_double)

! This is totally rediculous.  I don't know why this call to flush has to be
!   here, but on the SGI altix system, if it isn't here, then the job will not
!   run correctly.  THIS SHOULD BE FIXED IN THE FUTURE.
!call flush (20)
      enddo
   enddo

   ! Deallocate arrays that will not be used further.
   deallocate (typeSpinSplit)

end subroutine initPotStructures

subroutine setPotControlParameters (fbL,lastIt,corrCode,rlxFact,cTest,&
      & typeSpinSplitTemp)

   ! Use necessary modules.
   use O_Kinds

   implicit none

   ! Define dummy variables.
   integer :: fbL
   integer :: lastIt
   integer :: corrCode
   real (kind=double) :: rlxFact
   real (kind=double) :: cTest
   real (kind=double), dimension(:) :: typeSpinSplitTemp

   integer :: i
   !integer :: n
   integer :: info
   integer :: numCodes
   integer :: XC_CodeParam
   integer :: spinParam
   integer :: relParam
   integer :: GGAParam
   character(len=25) :: functionalName
   character(len=100) :: dataDirectory
   character(len=100) :: XC_CodeDataFile

   ! Set control parameters read from input.
   feedbacklevel   = fbL
   lastIteration   = lastIt
   XC_CODE         = corrCode
   relaxFactor     = rlxFact
   convgTest       = cTest

   ! Allocate space to hold the initially read in spin splitting for each type.
   allocate (typeSpinSplit(size(typeSpinSplitTemp)))

   typeSpinSplit(:) = typeSpinSplitTemp(:)

   ! Initialize control parameters.
   currIteration = 1
   converged     = 0

   ! open the xc_code.dat file
   call get_environment_variable("OLCAO_DATA", dataDirectory, info)
   XC_CodeDataFile=trim(dataDirectory)//"/xc_code.dat"

   open (unit=9, file=XC_CodeDataFile)

   ! Read past the header line and then get the total number of codes.
   read (9,*)
   read (9,*) numCodes

   ! Read each line(functional type). Once the correct one is found use
   ! it to set "spin", "rel", "GGA".
   do i = 1, numCodes
      read (9,*) functionalName, XC_CodeParam, spinParam, &
                                     & relParam, GGAParam
      if (XC_CodeParam.eq.XC_CODE) then
         spin = spinParam
         rel = relParam
         GGA = GGAParam
      endif
   enddo

end subroutine setPotControlParameters

subroutine initPotCoeffs

   ! Include the necessary modules
   use O_Kinds
   use O_CommandLine
   use O_PotTypes

   ! Define local variables
   integer :: i,j,k ! Loop index variables
   integer :: potTermCount
   real (kind=double) :: spaceHolder1 ! Gaussian exponential alphas
   real (kind=double) :: spaceHolder2 ! Total charge density
   real (kind=double) :: spaceHolder3 ! Valence charge density
   real (kind=double) :: spaceHolder4 ! Up - Down valence charge density.

   ! Allocate space for the potential coefficients.
   allocate (potCoeffs(potDim,spin))

   ! Read the existing potential coefficients for each term, or for the
   !   spin up and then spin down terms separately if we are doing a spin
   !   polarized calculation.
   read (8,*)  ! File header that says number of types.
   do i = 1, spin

      ! Initialize the counter of potential terms.
      potTermCount = 0

      read (8,*)  ! Read tag indicating spin up or spin down.
      do j = 1, numPotTypes
         read (8,*)  ! Type header that says the number of terms for this type.
         do k = 1, potTypes(j)%numAlphas

            ! Increment the counter.
            potTermCount = potTermCount + 1

            read (8,*) potCoeffs(potTermCount,i), spaceHolder1, spaceHolder2,&
               & spaceHolder3,spaceHolder4 
         enddo
      enddo
   enddo

end subroutine initPotCoeffs


subroutine cleanUpPotential

   implicit none

   deallocate (spinSplitFactor)
   deallocate (intgConsts)
   deallocate (potAlphas)

   ! This is allocated for main and intg but not other programs.
   if (allocated(potCoeffs)) then
      deallocate (potCoeffs)
   endif

end subroutine cleanUpPotential


end module O_Potential
