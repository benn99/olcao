module O_Populate

   ! Import necessary modules.
   use O_Kinds

   ! Make sure that no funny variables are defined.
   implicit none

   ! Define access
   public

   !!!!!!!!!!!!!!!!!!!!!!!!!!!!!
   ! Begin list of module data.!
   !!!!!!!!!!!!!!!!!!!!!!!!!!!!!

   ! Define module data.
   integer :: coreStructInit ! Flag for whether or not the core state
         ! structures have been initialized in an XANES/ELNES type calculation.
   integer :: occupiedEnergyIndex ! The index value of the highest occupied
         ! state in the sorted list.
   real (kind=double) :: occupiedEnergy ! The energy (in a.u.) that is the
         ! highest occupied state.
   real (kind=double), allocatable, dimension (:) :: sortedEnergyEigenValues
         ! This array holds all the energy eigen values of all kpoints and all
         ! spin states in sorted order from lowest to highest.
   real (kind=double), allocatable, dimension (:) :: electronPopulation
         ! This array holds the number of electrons in each of the kpoint, 
         !   spin states of the original unsorted energy eigen values.
   integer, allocatable, dimension (:) :: indexEnergyEigenValues
         ! This array holds a mapping between the original energy eigen values
         ! and a sorted list of the energy eigen values.  The index number in
         ! this array corresponds to the index number of the sorted energy
         ! eigen value array.  The value in this array corresponds to the index
         ! of the original unsorted array.  (Note that while the original
         ! array is not sorted, it is grouped by kpoint, spin, and then state.)
   integer, dimension(6,4) :: QN_nlOrderIndex ! The first index is the QN_n,
         ! and the second index is the QN_l+1 (because Fortran starts counting
         ! array indices at 1).  The value is the order of the state from
         ! lowest to higher energy in the ideal atom case.  The mixed filling
         ! of various states is not considered here (but it should be in the
         ! future especially since some basis set atoms may not fill in the
         ! ideal way.
   integer, dimension(13) :: numOrbitalStates ! For each of the above
         ! QN_nlOrderIndex values this records how many states there are for
         ! that orbital (including spin).
   integer :: excitedCoreStateIndex ! The band index number of the core state
         ! that is to be excited if a ELNES/XANES type calculation is being
         ! done.

   !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
   ! Begin list of module subroutines.!
   !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
   contains


! The population is done in two phases.  The first phase uses the old
!   standard technique and does not apply any thermal smearing to the
!   populated levels.  This phase is done ONLY to obtain the minimum
!   energy level that should be populated (which is trivial), and the
!   maximum energy level that should be populated (which is not trivial in
!   multi kpoint and excited state environments).

! The basic problem of doing spin polarized populations and also multi-
!   kpoint populations is that you don't know what the order of states is.
!   Is the lowest energy from kpoint #1 or kpoint #2?  How about the second
!   or third lowest?  Is the spin up from state #1 of kpoint #1 higher
!   energy than the spin down from state #2 of kpoint #1?  What about mixed
!   kpoints?

! The solution used here is to sort all the energy states and keep track of
!   where they came from.

! 1)  Split the energy levels on the first iteration of the SCF cycle for
!     spin polarized calculations only.
! 2)  Copy all the energy values into a 1 dimensional temp array.  The order
!     of the indices is important.  The values are put in by state first,
!     then spin, and finally kpoints.  So for a 4 state, 2 spin, 2 kpoint
!     system we would have:  111, 211, 311, 411, 121, 221, 321, 421, 112,
!     212, 312, 412, 122, 222, 322, 422.  Where the first digit of the
!     triplet is the state, the second is the spin, and the third is the
!     kpoint.   In the linear array the values are grouped first by their
!     kpoint (e.g. the first 8 are kpoint 1, and the second 8 are kpoint 2.)
!     Then, within the kpoint groups the values are grouped by spin.  (e.g.
!     the first 4 are spin up and the second 4 are spin down.)  Finally,
!     within the spin groups, the values are ordered by their state number.
!     This list is grouped, but not sorted.
! 3)  Sort the energy eigen values into a new array:
!     sortedEnergyEigenValues.  A mapping is created between the sorted
!     values and the original values grouped by kpoints, then spin, and then
!     state.  The mapping is held in indexEnergyEigenValues.  The index
!     number for this array corresponds to the index number for the sorted
!     array.  The value in the array is the index of the original unsorted
!     array.  (e.g. sortedArray = (2, 3, 6, 8) originalArray = (3, 6, 8, 2),
!     indexArray(1) = 4, indexArray(2) = 1, indexArray(3) = 2, and
!     indexArray(4) = 3.
! 4)  Now, the electron population for each state/kpoint/spin set is
!     computed.  The electron population array is one dimensional and the
!     indices for this array match the indices for the original unsorted
!     energy eigen value array.  The electron population for each triplet is
!     is then assigned IN THE ORDER OF THE INDEX ARRAY.  This will make the
!     lowest energy triplit the first to be populated, and the second lowest
!     triplet the next to be populated, etc.  ONE CATCH!  The amount of
!     electron popultion to go into a given triplet depends on which kpoint
!     that triplet includes.  FORTUNATELY, we thought ahead and grouped the
!     values according to their kpoint.  So, we just have to do a simple
!     integer division to get the kpoint number:
!     e.g. 1+(indexArray(i)-1) / (numStates*spin).  Once the cumulative
!     number of electrons is the same as the number of electrons in the
!     system, we abort the loop.
! 5)  There is one issue with the highest occupied state.  If it turns out
!     that this state is degenerate, then we need to distribute the charge
!     in all degenerate states evenly.  This will prevent the case of some
!     states being occupied while others at the same energy level are
!     totally unoccupied.  We find which states have the same energy and
!     then distribute the charge evenly among them by summing the total
!     charge that exists in the degenerate states and summing the total
!     charge that could be put in the degenerate states if they were all
!     completely filled.  Then, each state gets an amount of charge equal to
!     the kPoint weight of that state times the ratio of total existing over
!     total possible charge.  (NOTE that this scheme is NOT applied to the
!     thermal smearing phase.)
! 6)  The thermal smearing scheme is basically the same except that the
!     population is modified by the fermi function.
! 7)  The case of xanes calculation is also basically the same except that
!     we consider the system to have one extra electron, and then we remove
!     an electron from a core orbital after the system was completely
!     populated.


subroutine populateStates

   ! Import necessary modules.
   use O_Kinds
   use O_Constants
   use O_TimeStamps
   use O_Input ! For thermalSigma
   use O_CommandLine ! For excitedQN_n

   ! Make sure that there are not accidental variable declarations.
   implicit none

   ! Define the local variables used in this subroutine.

   ! Log the date and time we start.
   call timeStampStart (16)

   ! In the case that this is a XANES/ELNES type of calculation then we must
   !   initialize the core state structures if they have not yet been set up.
   if ((excitedQN_n /= 0) .and. (coreStructInit == 0)) then
      call initCoreStateStructures
   endif

   ! Always populate the states in the standard way.
!   print *, "populate Standard"
   call populateStandard
!   print *, "After populate Standard"

   ! If the thermal smearing parameter is non-zero, then we continue the
   !   population using the thermal smearing scheme.
   if (thermalSigma /= 0.0_double) then
      call populateSmearing
   endif

   ! Write out the calculated occupied energy (Fermi energy for metals) in eV.
   write (20,*) 'Highest Occupied Energy=',occupiedEnergy * hartree,' eV'
   call flush (20)

   ! Log the date and time we end.
   call timeStampEnd (16)

end subroutine populateStates


subroutine populateStandard

   ! Import necessary modules.
   use O_Kinds
   use O_Constants
   use O_CommandLine
   use O_Input
   use O_SecularEquation
   use O_KPoints
   use O_AtomicTypes
   use O_SortSubs
   use O_Potential

   ! Make sure that there are not accidental variable declarations.
   implicit none

   ! Define the local variables used in this subroutine.
   integer :: i,j,k ! Loop index variables
   integer :: tripletCounter ! Counts the total number of states in the system
         ! and is primarily used for tracking the index of various arrays.
   integer :: numSegments ! Records the number of segments in the energy


   ! Define variables used to populate the electron levels
   integer, allocatable, dimension (:) :: segmentBorders
   real (kind=double) :: populatedElectrons ! Tracks the total number of
         ! electrons (including fractional components) that have been assigned
         ! to energy levels ordered from lowest to highest over all kpoints.
   real (kind=double), allocatable, dimension (:) :: tempEnergyEigenValues

   ! Define variables to evenly fill the highest occupied degenerate states.
   integer :: minStateIndex
   integer :: maxStateIndex
   real (kind=double) :: possibleDegenCharge
   real (kind=double) :: degenerateCharge


   ! Allocate arrays and matrices for populating the electron levels
   ! These arrays will be deallocated in makeValenceRho after the kpoint
   !   loop because they are not needed until the next scf iteration after that
   !   point.
   allocate (electronPopulation      (numStates*numKPoints*spin))
   allocate (sortedEnergyEigenValues (numStates*numKPoints*spin))
   allocate (indexEnergyEigenValues  (numStates*numKPoints*spin))


   ! These arrays are used only for sorting and will be deallocated here.
   allocate (segmentBorders        (numStates*numKPoints*spin+1))
   allocate (tempEnergyEigenValues (numStates*numKPoints*spin))
!print *, "after declarations and allocations"
   ! Sort the energy eigen values in ascending order for populating.  This is
   !   done once at the beginning of this subroutine and the sorted order is
   !   used to populate the levels for both phases.

   ! Copy the energyEigenValues into the tempEnergyEigenValues single dimension
   !   array.  It is important to have the kpoints be the outer loop even if it
   !   is slower because we need the energyEigenValues sorted into groups based
   !   on their kpoint to assign the electron population easily later.
   tripletCounter = 0
   do i = 1, numKPoints
      do j = 1, spin
         do k = 1, numStates
            tripletCounter = tripletCounter + 1
            tempEnergyEigenValues(tripletCounter) = energyEigenValues(k,i,j)
         enddo
      enddo
   enddo


   ! Initialize the segment borders to each individual array slot.
!   print *, "numStates: ",numStates
!   print *, "numKPoints: ",numKPoints
!   print *, "Spin: ",spin
   numSegments = numStates * numKPoints * spin
   segmentBorders(1) = 0
   do i = 1, numSegments
      segmentBorders (i+1) = i
   enddo

!print *, "merge sort"
   ! Call the sorting subroutine
   call mergeSort (tempEnergyEigenValues,sortedEnergyEigenValues,&
         & indexEnergyEigenValues,segmentBorders,numSegments)

   ! Deallocate the unnecessary arrays from the sorting procedure.
   deallocate (segmentBorders)
   deallocate (tempEnergyEigenValues)


   ! Initialize the electron population of each level to 0.
   electronPopulation(:) = 0.0_double

   ! Initialize local variables
   populatedElectrons = 0.0_double ! Total number of populated electrons.


   ! The basic method is to fill the energy levels in order from the lowest
   !   energy level to the highest.  This is simple since we have just sorted
   !   the levels from lowest to highest.  Now we just fill them in with one
   !   exception.

   ! In the case where the level number is equal to the level number that has
   !   been depopulated by one electron due to xanes excitation.  The simplist
   !   method to deal with xanes calculations here is to populate all the
   !   levels in order as described above except consider the numElectron
   !   number to be larger by 1 than the real numElectron number.  Then we
   !   remove one electron worth of population value from each kpoint at the
   !   core excitation level.  This will put the excited electron in the lowest
   !   conduction band state and leave a core hole.
   

   ! First we determine if it is necessary to artificially increment the
   !   numElectrons in the system by one due to xanes excitation.
   if (excitedQN_n /= 0) then
      numElectrons = numElectrons + 1
   endif

!   print *, "do i = 1, numsegments",numSegments
!   flush(6)
   ! Consider each energy value and determine which KPoint it came from.  Then
   !   assign the appropriately weighted number of electrons to that state.
   do i = 1, numSegments

      ! Weight the electron population for this state by the kpoint weighting
      !   factor and divide by the spin value so that a spin-polarized
      !   calculation has one electron per state while a non-spin-polarized
      !   calculation has two electrons per state.  The value in the (x/y) will
      !   be a number from 0 to numKPoints-1 so we add one to that result to
      !   get the index for the kPointWeight.  The reason this works is because
      !   the energy values were grouped by their kpoints before sorting.
!      print *, "electron population set"
!   flush(6)
      electronPopulation(indexEnergyEigenValues(i)) = kPointWeight &
            & (1+(indexEnergyEigenValues(i)-1)/(numStates*spin)) / &
            & real(spin,double)

      ! Accumulate the electron population
!      print *, "accumulate electron pop"
!   flush(6)
      populatedElectrons = populatedElectrons + &
            & electronPopulation(indexEnergyEigenValues(i))

      ! Determine if the number of electrons that have been populated
      !   exceeds the number of electrons in the system.  If so, reduce the
      !   last populated level so that the total number of populated electrons
      !   equals the total number of electrons in the system.
!      print *, "some if thing"
      if (populatedElectrons > numElectrons) then

         ! First adjust the actual population.
         electronPopulation(indexEnergyEigenValues(i)) = kPointWeight &
            & (1+(indexEnergyEigenValues(i)-1)/(numStates*spin)) / &
            & real(spin,double) + numElectrons - populatedElectrons

         ! Then adjust the record of the number of populated electrons.
         populatedElectrons = numElectrons
!        print *, "after inside the if"
!   flush(6)
      endif

      ! Abort the loop when the last electron has been populated, recording
      !   the occupied energy (fermi energy for metals) as we leave.
!      print *, "second if"
      if (abs(numElectrons - populatedElectrons) < smallThresh) then
         occupiedEnergyIndex = i
         occupiedEnergy = sortedEnergyEigenValues(occupiedEnergyIndex)
         exit
      endif
!      print *, "end of iteration"
!   flush(6)
   enddo
!  print *, "after loop"
!   flush(6)
   ! Check for degeneracy of the highest occupied energy level.  If it is
   !   degenerate we need to find all the states that have the same energy and
   !   then distribute the electron population evenly to all of them.  If we
   !   do not do this in, for example, an isolated Fe atom then some of the d
   !   electron states would be occupied and others would not and the charge
   !   distribution would be very distorted.  The charge would never settle
   !   down and would keep flushing back and forth between the different d
   !   angular orientation sub-orbitals.  This will help with the convergence
   !   of metals too.


   ! Initialize to the case of no degenerate states.
!   print *, "initialize to no degenerate states"
!   print *, "indexEnergyEigenValues: ",indexEnergyEigenValues
!   print *, "occupiedEnergyIndex: ",occupiedEnergyIndex
!   print *, "len electronPopulats: ", size(electronPopulation,1)
!   flush(6)
   minStateIndex = occupiedEnergyIndex
   maxStateIndex = occupiedEnergyIndex
   degenerateCharge = electronPopulation(indexEnergyEigenValues( &
         & occupiedEnergyIndex))
   possibleDegenCharge = kPointWeight(1+(indexEnergyEigenValues &
            & (occupiedEnergyIndex)-1)/(numStates*spin)) / real(spin,double)

   ! The way to check for degeneracy is to first assume that the last populated
   !   state is not degenerate and then search higher and lower energy states
   !   to see if they are at a similar energy.
!   print *, "do while something"
!   flush(6)
   do while (abs(occupiedEnergy - sortedEnergyEigenValues(maxStateIndex+1)) <= &
         & smallThresh)

      ! Increment the index counter.
      maxStateIndex = maxStateIndex + 1

      ! Accumulate the amount of charge that *could* be held in the degenerate
      !   states.  (The possible charge.)
      possibleDegenCharge = possibleDegenCharge + kPointWeight &
            & (1+(indexEnergyEigenValues(maxStateIndex)-1)/(numStates*spin))/&
            & real(spin,double)

      ! Abort if we reach the bounds of the calculation.
      if (maxStateIndex == numKPoints * numStates * spin) exit
   enddo
   do while (abs(occupiedEnergy - sortedEnergyEigenValues(minStateIndex-1)) <= &
         & smallThresh)

      ! Decrement the index counter.
      minStateIndex = minStateIndex - 1

      ! Accumulate the amount of charge that *could* be held in the degenerate
      !   states.  (The possible charge.)
      possibleDegenCharge = possibleDegenCharge + kPointWeight &
            & (1+(indexEnergyEigenValues(minStateIndex)-1)/(numStates*spin))/&
            & real(spin,double)

      ! Accumulate the amount of existing charge.
      degenerateCharge = degenerateCharge + kPointWeight &
            & (1+(indexEnergyEigenValues(minStateIndex)-1)/(numStates*spin))/&
            & real(spin,double)

       ! Abort if we reach the bounds of the calculation.
      if (minStateIndex == 1) exit
   enddo

   
   ! For each of the degenerate states redistribute the charge evenly.
   do i = minStateIndex, maxStateIndex
      electronPopulation(indexEnergyEigenValues(i)) = degenerateCharge / &
            & possibleDegenCharge * kPointWeight &
            & (1+(indexEnergyEigenValues(i)-1)/(numStates*spin)) / &
            & real(spin,double)
   enddo

   ! Adjust the occupied energy and occupied energy index.
   occupiedEnergyIndex = maxStateIndex
   occupiedEnergy = sortedEnergyEigenValues(occupiedEnergyIndex)


   ! Now that all the levels have been populated we remove an electron from
   !   the level that had a xanes excitation applied to it (if applicable).
!   print *, "thing for xanes"
   if (excitedQN_n /= 0) then
      call correctCorePopulation
   endif
!  print *, "end of pop standard"
end subroutine populateStandard


subroutine populateSmearing

   ! Import necessary modules.
   use O_Kinds
   use O_CommandLine
   use O_Input
   use O_KPoints
   use O_MathSubs
   use O_Potential

   ! Make sure that there are not accidental variable declarations.
   implicit none

   ! Define the local variables used in this subroutine.
   integer :: i,j
   integer :: numSegments
   real (kind=double) :: smearingRange
   real (kind=double) :: minEnergyInit
   real (kind=double) :: maxEnergyInit
   real (kind=double) :: minEnergy
   real (kind=double) :: maxEnergy
   real (kind=double) :: chargeSum

   ! Compute the number of energy eigen value terms.
   numSegments = numStates * numKPoints * spin

   ! Define the initial border extension range due to thermal smearing.  The
   !   number chosen here is so that it is larger than any reasonable
   !   electronic gap.  The unit here is atomic units, not eV.
   smearingRange = 10

   ! Obtain the energy of the lowest populated level and the energy of the 
   !   highest populated level as determined from phase one.

   ! Initialize with values from the first kpoint.
   minEnergyInit = sortedEnergyEigenValues(1)
   maxEnergyInit = sortedEnergyEigenValues(occupiedEnergyIndex)

   ! Adjust the min and max boundaries from the initial values by the thermal
   !   smearing range.
   minEnergy = minEnergyInit
   maxEnergy = maxEnergyInit + smearingRange

   ! Begin a search for the Fermi energy.  500 iterations should be enough. :)
   do i = 1,500

      ! Now we have to repeat something similar to the first phase.  We will
      !   fill the energy levels in order again.

      ! So first we determine if it is necessary to artificially increment the
      !   numElectrons in the system by one due to xanes excitation.
      if (excitedQN_n /= 0) then
         numElectrons = numElectrons + 1
      endif

      ! Make an initial guess for the Fermi energy (occupiedEnergy) as being
      !   between the two border points.
      occupiedEnergy = 0.5_double * (minEnergy + maxEnergy)

      ! Initialize the counter of the number of electrons populated so far.
      chargeSum = 0.0_double

      ! Start populating every state for every kpoint.
      do j = 1, numSegments


         ! Weight the electron population for this state by the kpoint 
         !   weighting factor and divide by the spin value so that a
         !   spin-polarized calculation has one electron per state while a
         !   non-spin-polarized calculation has two electrons per state.  Then
         !   multiply by a smeared step function to smear the population.
         electronPopulation(indexEnergyEigenValues(j)) = (kPointWeight &
               & (1+(indexEnergyEigenValues(j)-1)/(numStates*spin)) / &
               & real(spin,double)) * stepFunction(( &
               & sortedEnergyEigenValues(j)-occupiedEnergy) / thermalSigma)

         ! Accumulate the electron population
         chargeSum = chargeSum + electronPopulation(indexEnergyEigenValues(j))

      enddo

      ! Now that all the levels have been populated we remove an electron from
      !   the core level that had an excitation applied to it (if applicable).
      if (excitedQN_n /= 0) then  ! If not a ground state type calculation.
         call correctCorePopulation
      endif

      ! If the difference in charge between the correct nummElectrons and the
      !   the just assigned chargeSum is sufficiently small then we can exit
      !   the population outer (i) loop since we have found the correct
      !   population values, and Fermi level.
      if (abs(chargeSum - numElectrons) < smallThresh) then
         exit
      endif


      ! Move the correct border value to the position of the last
      !   Fermi energy.  The Fermi energy will be re-guessed in the next
      !   iteration.
      if (chargeSum < numElectrons) then
         minEnergy = occupiedEnergy
      else
         maxEnergy = occupiedEnergy
      endif
   enddo

end subroutine populateSmearing


subroutine correctCorePopulation

   ! Import necessary modules.
   use O_Kinds
   use O_Constants
   use O_CommandLine
   use O_SecularEquation
   use O_KPoints
   use O_Input
   use O_Potential

   ! Make sure that there are not accidental variable declarations.
   implicit none

   ! Define the local variables used in this subroutine.
   integer :: i
   integer :: initialState
   integer :: finalState

   ! Core occupation should proceed in the following order:
   !   1s, 2s, 2p, 3s, 3p, 4s, 3d, 4p, 5s, 4d, 5p, 6s, 4f
   ! This was assumed when assigning the excitedCoreStateIndex and the values
   !   in the numOrbitalStates(:,:) array.

   ! The initial state must begin at the next state after all the states lower
   !   than the excitedCoreStateIndex.  (excitedCoreStateIndex-1) is the band
   !   index of the state just below the excited core state.  The numKPoints
   !   will get us past all copies of this state at each kPoint.  The spin will
   !   get us past the spin degenerate core states (this will not be true if
   !   we include spin-orbit coupling so it will be necessary to devise a
   !   better way to select the states to be excited).  The +1 is then the
   !   next higher state.
   initialState = numKPoints * (excitedCoreStateIndex-1) * spin + 1

   ! The final state must be the last of the states of the same orbital type as
   !   the initial state.  We simply add to the initial state the number of
   !   states in this orbital type and multiply by the kpoint and spin factors.
   !   The -1 is the last state (without it we would mark the next higher
   !   orbital).
   finalState = initialState + numKPoints * spin * &
         & numOrbitalStates(QN_nlOrderIndex(excitedQN_n,excitedQN_l+1)) - 1

   ! Remove a fraction of an electron from every kpoint/spin pair for the
   !   choice of QN_n, QN_l states.
   do i = initialState, finalState
      electronPopulation(indexEnergyEigenValues(i)) = &
            & electronPopulation(indexEnergyEigenValues(i)) - &
            & electronPopulation(indexEnergyEigenValues(i)) * &
            & real(spin,double) / 2.0_double / &
            & numOrbitalStates(QN_nlOrderIndex(excitedQN_n,excitedQN_l+1))
   enddo

   ! We also restore the local numElectrons variable for the next part of
   !   the OLCAO calculation that may rely on it.
   numElectrons = numElectrons - 1

end subroutine correctCorePopulation


subroutine initCoreStateStructures

   ! Import necessary modules.
   use O_Kinds
   use O_CommandLine ! excitedQN_n, and excitedQN_l
   use O_Potential   ! For spin

   ! Make sure that nothing funny is accidentally used.
   implicit none

   ! Define local variables.
   integer :: i

   ! Core occupation should proceed in the following order:
   !   1s, 2s, 2p, 3s, 3p, 4s, 3d, 4p, 5s, 4d, 5p, 6s, 4f

   ! Associate each possible QN_n,QN_l combination with an index number that
   !   represents the order that this pair is supposed to appear from lowest
   !   energy to highest.  (Applies only to states up to 4f as this is the
   !   highest "core" state considered.)
   QN_nlOrderIndex(1,1) = 1
   QN_nlOrderIndex(2,1) = 2
   QN_nlOrderIndex(2,2) = 3
   QN_nlOrderIndex(3,1) = 4
   QN_nlOrderIndex(3,2) = 5
   QN_nlOrderIndex(4,1) = 6
   QN_nlOrderIndex(3,3) = 7
   QN_nlOrderIndex(4,2) = 8
   QN_nlOrderIndex(5,1) = 9
   QN_nlOrderIndex(4,3) = 10
   QN_nlOrderIndex(5,2) = 11
   QN_nlOrderIndex(6,1) = 12
   QN_nlOrderIndex(4,4) = 13

   ! Record the number of states associated with each QN_n,QN_l by index number.
   numOrbitalStates(1)  = 1
   numOrbitalStates(2)  = 1
   numOrbitalStates(3)  = 3
   numOrbitalStates(4)  = 1
   numOrbitalStates(5)  = 3
   numOrbitalStates(6)  = 1
   numOrbitalStates(7)  = 5
   numOrbitalStates(8)  = 3
   numOrbitalStates(9)  = 1
   numOrbitalStates(10) = 5
   numOrbitalStates(11) = 3
   numOrbitalStates(12) = 1
   numOrbitalStates(13) = 7
   numOrbitalStates(:) = numOrbitalStates(:) * spin

   ! Determine the band index number of the requested core excitation
   !   (excluding the ground state of course).
   if (excitedQN_n /= 0) then

      ! Initialize the core state index number.
      excitedCoreStateIndex = 0

      ! Accumulate all the states except the core state to be excited.
      do i = 1, QN_nlOrderIndex(excitedQN_n,excitedQN_l+1) - 1
         excitedCoreStateIndex = excitedCoreStateIndex + numOrbitalStates(i)
      enddo

      ! Increment by 1 to have the index number of the core state.
      excitedCoreStateIndex = excitedCoreStateIndex + 1
   endif

   ! Turn on the flag indicating that the core state structures have been
   !   initialized.
   coreStructInit = 1

end subroutine initCoreStateStructures


subroutine cleanUpPopulation

   implicit none

   deallocate (electronPopulation)
   deallocate (sortedEnergyEigenValues)
   deallocate (indexEnergyEigenValues)

end subroutine cleanUpPopulation

end module O_Populate
