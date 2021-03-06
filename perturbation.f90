module perturbation_mod

    use kinds_mod
    USE variables
    use communicate
    use mpi
    use module_sparse
    use BLAS95
    use F95_precision
    use mathlib
    use basisindex_mod

    implicit none
    real(kind=r8),allocatable ::  Hdiagp(:),correctenergy2(:),correctenergy3(:),&
                    H0lr(:,:)
    integer :: ngoodstatesp
    logical :: Ifperturbation3,IfperturbationDVD

contains
!================================================================
!================================================================

subroutine perturbation(eigenvalue,num,direction)
    use ABop
    implicit none

    integer,intent(in) :: num
    character(len=1),intent(in) :: direction
    real(kind=r8) :: eigenvalue(:)
    integer :: istate
    real(kind=r8) :: starttime,endtime


    call master_print_message("enter in Perturbation Subroutine")
    
    allocate(correctenergy2(nstate))
    allocate(correctenergy3(nstate))
    correctenergy2=0.0D0
    correctenergy3=0.0D0
 
    call basisindex(4*Lrealdimp,4*Rrealdimp,quantabigLp(1:4*Lrealdimp,1:2),quantabigRp(1:4*Rrealdimp,1:2),&
        ngoodstatesp,goodbasisp,goodbasiscolp(1:4*Rrealdimp+1))

    if(opmethod=="comple") then
        call Complement(operamatbig1p,bigcolindex1p,bigrowindex1p,Lrealdimp,Rrealdimp,subMp,1)
    end if

    ! Get the diagonal element in the 4Mp*4Mp basis
    call GetHdiagp
    
    call CopyCoeff2Coeffp
    
    if(myid==0) then
        allocate(H0lr(ngoodstatesp,nstate))
        H0lr=0.0D0
    end if
    
    call master_print_message( "Perturbation Correct Energy")
    if(Lrealdimp>Lrealdim .or. Rrealdimp>Rrealdim) then

        starttime=MPI_WTIME()
        call correct_coeff(eigenvalue,num)
        endtime=MPI_WTIME()
        call master_print_message(endtime-starttime,"2nd Perturbation TIME:")
        
        if(ifperturbation3==.true. .and. nleft==(norbs-1)/2 .and. direction=="l") then
            ! since 3rd perturbation energy is not related to the wavefunction;
            ! so it can be done only in the middle of each sweep
            starttime=MPI_WTIME()
            call CorrectEOrder3(eigenvalue,num)
            endtime=MPI_WTIME()
            call master_print_message(endtime-starttime,"3rd Perturbation TIME:")
        end if
    end if

    if(myid==0) then
        do istate=1,nstate,1
            write(*,*) "istate=",istate
            write(*,*) "0th Order:",0.0D0,eigenvalue(istate)
            
            eigenvalue(istate)=correctenergy2(istate)+eigenvalue(istate)
            write(*,*) "2nd Order:",correctenergy2(istate),eigenvalue(istate)
            
            if(Ifperturbation3==.true. .and. nleft==(norbs-1)/2 .and. direction=="l") then
                eigenvalue(istate)=correctenergy3(istate)+eigenvalue(istate)
                write(*,*) "3rd Order:",correctenergy3(istate),eigenvalue(istate)
            end if
        end do
    end if
    
    ! in the middle of every sweep do Perturbation space Diagnolization
    if(nleft==(norbs-1)/2 .and. direction=="l" .and. IfperturbationDVD==.true.) then
        starttime=MPI_WTIME()
        call PerturbationSpaceDvD(eigenvalue)
        endtime=MPI_WTIME()
        call master_print_message(endtime-starttime,"Perturbation Space DVD TIME:")
    end if
    
    if(opmethod=="comple") then 
        call deallocate_Complement
    end if

    if(ifopenperturbation==.true.) then
    if(myid==0) then
    ! update the sweepenergy
    ! use the middle site as the sweepenergy
        if(nleft==(norbs+1)/2-1) then
            do istate=1,nstate,1
                sweepenergy(isweep,istate)=eigenvalue(istate)
            end do
        end if
        ! update the energy
        dmrgenergy(1:nstate)=eigenvalue(1:nstate)
    end if
    end if
    
    if(myid==0) then
        deallocate(H0lr)
        deallocate(Hdiagp)
    end if
    deallocate(correctenergy2)
    deallocate(correctenergy3)
return

end subroutine perturbation

!================================================================
!================================================================

subroutine CopyCoeff2Coeffp
! this subroutine copy the CoeffIF in CSR format to coordinate format CoeffIfp
    implicit none
    integer :: istate
    integer :: job(8),info,i
    integer :: remainder,rowindex,basisindex1,num,firstindex,lastindex
    
    
    if(myid==0) then
        job(1)=0
        job(2)=1
        job(3)=1
        job(5)=coeffIFdim
        job(6)=3
        
        coeffIFp(1:ngoodstatesp,1:nstate)=0.0D0
        ! only get the coordinate structure
        call mkl_dcsrcoo(job, 4*Lrealdim, CoeffIF(:,1), CoeffIFcolindex(:,1), CoeffIFrowindex(:,1),&
            CoeffIFplast , CoeffIfp(:,1), CoeffIFrowindexp, CoeffIFcolindexp, info)
        if(info/=0) then
            call master_print_message(info,"in CopyCoeff2Coeffp info/=0")
        end if
        CoeffIfp(:,1)=0.0D0

        do i=1,CoeffIfplast,1
            remainder=mod(coeffIfrowindexp(i),Lrealdim)
            if(remainder==0) then
                rowindex=(coeffIfrowindexp(i)/Lrealdim-1)*Lrealdimp+Lrealdim
            else
                rowindex=(coeffIfrowindexp(i)/Lrealdim)*Lrealdimp+remainder
            end if

            firstindex=goodbasiscolp(coeffIFcolindexp(i))
            lastindex=goodbasiscolp(coeffIFcolindexp(i)+1)-1
            num=lastindex-firstindex+1
            call BinarySearch(num,goodbasisp(firstindex:lastindex,1),rowindex,basisindex1)
            if(basisindex1==0) then
                write(*,*) "basisindex1==0" 
                stop
            end if
            basisindex1=basisindex1+firstindex-1
            do istate=1,nstate,1
                CoeffIFp(basisindex1,istate)=CoeffIF(i,istate)
            end do
        end do
        call scopy(ngoodstatesp,goodbasisp(1,1),1,coeffIFrowindexp(1),1)
        call scopy(ngoodstatesp,goodbasisp(1,2),1,coeffIFcolindexp(1),1)
    end if
return
end subroutine CopyCoeff2Coeffp

!================================================================
!================================================================

subroutine correct_coeff(eigenvalue,num)
    use blas95
    use F95_precision
    
    implicit none
    integer,intent(in) :: num
    real(kind=r8),intent(in) :: eigenvalue(:)
    integer :: remainder
    integer :: istate,ibasis
    real(kind=r8) :: norm
    
    ! the GetH0lr1 is much efficient than the GetH0lr2
    ! because it calculate the H0j' at one time
    call GetH0lr1
   !call GetH0lr2

    if(myid==0) then
        do ibasis=1,ngoodstatesp,1
            remainder=mod(goodbasisp(ibasis,1),Lrealdimp)
            if(remainder==0) remainder=Lrealdimp
            if(goodbasisp(ibasis,2)<=4*Rrealdim .and. remainder<=Lrealdim) then
                cycle
            else
                coeffIFplast=coeffIFplast+1
                do istate=1,nstate,1
                    CoeffIFp(ibasis,istate)=H0lr(ibasis,istate)/(eigenvalue(istate)-Hdiagp(ibasis))
                    correctenergy2(istate)=correctenergy2(istate)+H0lr(ibasis,istate)*&
                        H0lr(ibasis,istate)/(eigenvalue(istate)-Hdiagp(ibasis))
                end do
            end if
        end do

        do istate=1,nstate,1
            norm=dot(coeffIFp(1:coeffIFplast,istate),coeffIFp(1:coeffIFplast,istate))
            write(*,*) "Perturbation normalization:",istate,norm
            norm=sqrt(norm)
            coeffIFp(1:coeffIFplast,istate)=coeffIFp(1:coeffIFplast,istate)/norm
        end do

        if(coeffIFplast/=ngoodstatesp) then
            write(*,*) "coeffIFplast/=ngoodstatesp",coeffIFplast,ngoodstatesp
            stop
        end if
    end if

    return
end subroutine correct_coeff

!================================================================
!================================================================

subroutine GetH0lr1
    use ABop
    implicit none
    
    ! local 
    real(kind=r8),allocatable :: H0k(:,:),H0kout(:,:)
    integer(kind=i4),allocatable :: coeffIFrowindexdummy(:,:)
    integer :: i,istate,k,j,ibasis
    integer :: remainder

    if(myid==0) then
        allocate(H0k(ngoodstatesp,nstate))
        allocate(H0kout(ngoodstatesp,nstate))
        allocate(coeffIFrowindexdummy(4*subM+1,nstate))
        H0k=0.0D0
        H0kout=0.0D0
        
        do istate=1,nstate,1
            call CSCtoCSR('RC',4*Rrealdim,4*Lrealdim,&
            coeffIF(:,istate),coeffIFcolindex(:,istate),coeffIFrowindex(:,istate),&
            coeffIFrowindexdummy(:,istate))
        end do
        
        k=0
        do ibasis=1,ngoodstatesp,1
            remainder=mod(goodbasisp(ibasis,1),Lrealdimp)
            if(remainder==0) remainder=Lrealdimp
            if(goodbasisp(ibasis,2)<=4*Rrealdim .and. remainder<=Lrealdim) then
                k=k+1
                H0k(ibasis,1:nstate)=coeffIF(k,1:nstate)
            end if
        end do

        if(k/=ngoodstates) then
            write(*,*) "GetH0lr1 k/=ngoodstates",k,ngoodstates
            stop
        end if

        do istate=1,nstate,1
            call CSCtoCSR('CR',4*Lrealdim,4*Rrealdim,&
            coeffIF(:,istate),coeffIFcolindex(:,istate),coeffIFrowindexdummy(:,istate),&
            coeffIFrowindex(:,istate))
        end do

        deallocate(coeffIFrowindexdummy)
    end if
    
    if(opmethod=="comple") then

        ! calculate sigma(i<inner space) Hji'*Ci0
        call op(ngoodstatesp,nstate,H0k,H0kout,&
                Lrealdimp,Rrealdimp,subMp,ngoodstatesp,&
                operamatbig1p,bigcolindex1p,bigrowindex1p,&
                Hbigp,Hbigcolindexp,Hbigrowindexp,&
                quantabigLp,quantabigRp,goodbasisp,goodbasiscolp)
        
    else if(opmethod=="direct") then
        call opdirect(ngoodstatesp,nstate,H0k,H0kout,&
                Lrealdimp,Rrealdimp,subMp,ngoodstatesp,&
                operamatbig1p,bigcolindex1p,bigrowindex1p,&
                Hbigp,Hbigcolindexp,Hbigrowindexp,&
                quantabigLp,quantabigRp,goodbasisp,goodbasiscolp)
    else
        stop
    end if

    if(myid==0) then
        ! matrix operation
        H0lr=H0kout
        deallocate(H0k,H0kout)
        
        do ibasis=1,ngoodstatesp,1
            remainder=mod(goodbasisp(ibasis,1),Lrealdimp)
            if(remainder==0) remainder=Lrealdimp
            if(goodbasisp(ibasis,2)<=4*Rrealdim .and. remainder<=Lrealdim) then
                H0lr(ibasis,1:nstate)=0.0D0
            end if
        end do
    end if

    return
    
end subroutine GetH0lr1

!================================================================
!================================================================

subroutine GetH0lr2
    implicit none
    
    integer :: ngoodstatespdummy,remainder
    integer :: i,j,k
    real(kind=r8) :: Hij(nstate)

    ngoodstatespdummy=0
    do i=1,4*Rrealdimp,1
    do j=1,4*Lrealdimp,1
        if((quantabigLp(j,1)+quantabigRp(i,1)==nelecs) .and. &
        quantabigLp(j,2)+quantabigRp(i,2)==totalSz) then
            ngoodstatespdummy=ngoodstatespdummy+1
            
            remainder=mod(j,Lrealdimp)
            if(remainder==0) remainder=Lrealdimp
            if(i<=4*Rrealdim .and. remainder<=Lrealdim) then
                cycle
            else
                call GetHmat(j,i,Hij)
                if(myid==0) then
                    H0lr(ngoodstatespdummy,1:nstate)=Hij(1:nstate)
                end if
            end if
        end if
    end do
    end do

    return
end subroutine GetH0lr2

!================================================================
!================================================================

subroutine GetHdiagp
    
    use GetHdiag_mod
    implicit none
    integer :: i,j

    if(myid==0) allocate(HDiagp(ngoodstatesp))
    
    if(myid==0) then
        write(*,*) "ngoodstatesp=",ngoodstatesp
    end if

    call GetHDiag(Hdiagp,ngoodstatesp,&
        operamatbig1p,bigcolindex1p,bigrowindex1p,&
        Hbigp,Hbigcolindexp,Hbigrowindexp,&
        goodbasisp,.true.)
    
!   if(myid==0) then
!       write(*,*) Hdiagp
!   end if
    return
end subroutine GetHDiagp

!================================================================
!================================================================
    
subroutine GetHmat(lindex,rindex,Hlr)

! this subroutine get the Hij element

    implicit none
    
    integer :: lindex,rindex
    real(kind=r8) :: Hlr(nstate)
    
    ! local
    integer :: istate
    character(len=1) :: formation(6)
    real(kind=r8),allocatable :: vectorR(:),vectorL(:),vector0(:,:),&
                    vectorRhop(:,:),vectorLhop(:,:),vector0hop(:,:,:)
    real(kind=r8) :: phase(4),dummyHij(nstate)
    integer :: i,j,l,k,iproc,ll
    integer :: operaindex
    logical :: ifhop
    integer :: status(MPI_STATUS_SIZE)
    integer :: ierr
    integer :: remainder,factor
    
    allocate(vectorR(4*Rrealdim))
    allocate(vectorL(4*Lrealdim))
    allocate(vector0(4*Lrealdim,nstate))
    
    !  no need to calculate HL*1 and 1*HR 
    !  it's zero definitely
    
    formation(1)='G'
    formation(2)='L'
    formation(3)='N'
    formation(4)='F'
    
    ! initialize the Hij in every process
    dummyHij(1:nstate)=0.0D0
    ! HL*1 and 1*HR term
    if(myid==0) then
        ! HL*1
        if(rindex>=1 .and. rindex<=4*Rrealdim) then
            vectorR=0.0D0
            vectorR(rindex)=1.0D0
            do istate=1,nstate,1
                call mkl_dcsrmv('N',4*Lrealdim,4*Rrealdim,1.0D0,formation,coeffIF(:,istate),&
                    coeffIfcolindex(:,istate),coeffIFrowindex(1:4*Lrealdim,istate),&
                    coeffIFrowindex(2:4*Lrealdim+1,istate),vectorR,0.0D0,vector0(:,istate))
            end do
            do ll=1,4,1
                call GetSpmat1Vec(4*Lrealdimp,lindex,(ll-1)*Lrealdimp+1,(ll-1)*Lrealdimp+Lrealdim,Hbigp(:,1),Hbigcolindexp(:,1),Hbigrowindexp(:,1),&
                    "row",Lrealdim,vectorL((ll-1)*Lrealdim+1:ll*Lrealdim))
            end do
            do istate=1,nstate,1
                dummyHij(istate)=dot(vectorL,vector0(:,istate))+dummyHij(istate)
            end do
        end if
        ! 1*HR term
        remainder=mod(lindex,Lrealdimp)
        if(remainder==0) then
            remainder=Lrealdimp
            factor=lindex/Lrealdimp-1
        else
            factor=lindex/Lrealdimp
        end if
        if(remainder<=Lrealdim) then
            vectorL=0.0D0
            vectorL(factor*Lrealdim+remainder)=1.0D0
            call GetSpmat1Vec(4*Rrealdimp,rindex,1,4*Rrealdim,Hbigp(:,2),Hbigcolindexp(:,2),Hbigrowindexp(:,2),&
                "row",4*Rrealdim,vectorR)
            do istate=1,nstate,1
                call mkl_dcsrmv('N',4*Lrealdim,4*Rrealdim,1.0D0,formation,coeffIF(:,istate),&
                    coeffIfcolindex(:,istate),coeffIFrowindex(1:4*Lrealdim,istate),&
                    coeffIFrowindex(2:4*Lrealdim+1,istate),vectorR,0.0D0,vector0(:,istate))
            end do
            do istate=1,nstate,1
                dummyHij(istate)=dot(vectorL,vector0(:,istate))+dummyHij(istate)
            end do
        end if
    end if

    ! pppV term
    if(logic_PPP==1) then   ! in the hubbard model no need do this calculation
        do i=norbs,norbs-nright,-1
            if(myid==orbid1(i,1)) then
                operaindex=orbid1(i,2)*3
                call GetSpmat1Vec(4*Rrealdimp,rindex,1,4*Rrealdim,operamatbig1p(:,operaindex),bigcolindex1p(:,operaindex),bigrowindex1p(:,operaindex),&
                    "row",4*Rrealdim,vectorR)
                call MPI_SEND(vectorR,4*Rrealdim,MPI_real8,0,i,MPI_COMM_WORLD,ierr)
            else if(myid==0) then
                call MPI_RECV(vectorR,4*Rrealdim,MPI_real8,orbid1(i,1),i,MPI_COMM_WORLD,status,ierr)
                do istate=1,nstate,1
                    call mkl_dcsrmv('N',4*Lrealdim,4*Rrealdim,1.0D0,formation,coeffIF(:,istate),&
                        coeffIfcolindex(:,istate),coeffIFrowindex(1:4*Lrealdim,istate),&
                        coeffIFrowindex(2:4*Lrealdim+1,istate),vectorR,0.0D0,vector0(:,istate))
                end do
            end if

            do iproc=1,nprocs-1
                if(myid==iproc .or. myid==0) then
                    do l=1,nleft+1,1
                        if(orbid1(l,1)==iproc) then
                            if(myid==0) then
                                call MPI_SEND(vector0,4*Lrealdim*nstate,MPI_real8,iproc,0,MPI_COMM_WORLD,ierr)
                                exit
                            else
                                call MPI_RECV(vector0,4*Lrealdim*nstate,MPI_real8,0,0,MPI_COMM_WORLD,status,ierr)
                                exit
                            end if
                        end if
                    end do
                end if
            end do
            
            do l=1,nleft+1,1
                if(myid==orbid1(l,1)) then
                    operaindex=orbid1(l,2)*3
                    do ll=1,4,1
                        call GetSpmat1Vec(4*Lrealdimp,lindex,(ll-1)*Lrealdimp+1,(ll-1)*Lrealdimp+Lrealdim,operamatbig1p(:,operaindex),bigcolindex1p(:,operaindex),bigrowindex1p(:,operaindex),&
                            "row",Lrealdim,vectorL((ll-1)*Lrealdim+1:ll*Lrealdim))
                    end do
                    do istate=1,nstate,1
                        dummyHij(istate)=dot(vectorL,vector0(:,istate))*pppV(i,l)+dummyHij(istate)
                    end do
                end if
            end do
        end do
    end if

    allocate(vectorRhop(4*Rrealdim,4))
    allocate(vectorLhop(4*Lrealdim,4))
    allocate(vector0hop(4*Lrealdim,4,nstate))

    ! hopping term
    do i=norbs,norbs-nright,-1
        ! check if need hopping matrix
        ifhop=.false.
        do j=1,nleft+1,1
            if(bondlink(i,j)==1) then
                ifhop=.true.
                exit
            end if
        end do
        
        ! in hop
        ! col is <RA|a^+|RI>,row <RI|a^+|RA>=<RA|a|RI>
        if(ifhop==.true.) then
            if(myid==orbid1(i,1)) then
                operaindex=orbid1(i,2)*3
                do k=1,2,1
                    ! 1: up row 2: down row 3: up col 4: down col
                    ! up/down spin row
                    call GetSpmat1Vec(4*Rrealdimp,rindex,1,4*Rrealdim,operamatbig1p(:,operaindex-3+k),&
                        bigcolindex1p(:,operaindex-3+k),bigrowindex1p(:,operaindex-3+k),&
                        "row",4*Rrealdim,vectorRhop(:,k))
                    ! up/down spin col
                    call GetSpmat1Vec(4*Rrealdimp,rindex,1,4*Rrealdim,operamatbig1p(:,operaindex-3+k),&
                        bigcolindex1p(:,operaindex-3+k),bigrowindex1p(:,operaindex-3+k),&
                        "col",4*Rrealdim,vectorRhop(:,2+k))
                end do
                call MPI_SEND(vectorRhop,16*Rrealdim,MPI_real8,0,i,MPI_COMM_WORLD,ierr)
            else if(myid==0) then
                call MPI_RECV(vectorRhop,16*Rrealdim,MPI_real8,orbid1(i,1),i,MPI_COMM_WORLD,status,ierr)
                do istate=1,nstate,1
                do k=1,4,1
                    call mkl_dcsrmv('N',4*Lrealdim,4*Rrealdim,1.0D0,formation,coeffIF(:,istate),&
                    coeffIfcolindex(:,istate),coeffIFrowindex(1:4*Lrealdim,istate),&
                    coeffIFrowindex(2:4*Lrealdim+1,istate),vectorRhop(:,k),0.0D0,vector0hop(:,k,istate))
                end do
                end do
            end if

            do iproc=1,nprocs-1
                if(myid==iproc .or. myid==0) then
                    do l=1,nleft+1,1
                        if(bondlink(i,l)==1 .and. orbid1(l,1)==iproc) then
                            if(myid==0) then
                                call MPI_SEND(vector0hop,16*Lrealdim*nstate,MPI_real8,iproc,0,MPI_COMM_WORLD,ierr)
                                exit
                            else
                                call MPI_RECV(vector0hop,16*Lrealdim*nstate,MPI_real8,0,0,MPI_COMM_WORLD,status,ierr)
                                exit
                            end if
                        end if
                    end do
                end if
            end do
            
            ! Left space do the calculation
            do l=1,nleft+1,1
                if(myid==orbid1(l,1) .and. bondlink(i,l)==1) then
                    operaindex=orbid1(l,2)*3
                    do k=1,2,1
                        do ll=1,4,1
                            call GetSpmat1Vec(4*Lrealdimp,lindex,(ll-1)*Lrealdimp+1,(ll-1)*Lrealdimp+Lrealdim,operamatbig1p(:,operaindex-3+k),&
                                bigcolindex1p(:,operaindex-3+k),bigrowindex1p(:,operaindex-3+k),&
                                "row",Lrealdim,vectorLhop((ll-1)*Lrealdim+1:ll*Lrealdim,k))
                            call GetSpmat1Vec(4*Lrealdimp,lindex,(ll-1)*Lrealdimp+1,(ll-1)*Lrealdimp+Lrealdim,operamatbig1p(:,operaindex-3+k),&
                                bigcolindex1p(:,operaindex-3+k),bigrowindex1p(:,operaindex-3+k),&
                                "col",Lrealdim,vectorLhop((ll-1)*Lrealdim+1:ll*Lrealdim,k+2))
                        end do
                    end do
                    phase(1:4)=(-1.0D0)**(mod(quantabigLp(lindex,1),2)+1)
                    phase(3:4)=phase(3:4)*(-1.0D0)
                    do istate=1,nstate,1
                        do k=1,2,1
                            dummyHij(istate)=dot(vectorLhop(:,k),vector0hop(:,k+2,istate))*t(i,l)*phase(k)+dummyHij(istate)
                        end do
                        do k=3,4,1
                            dummyHij(istate)=dot(vectorLhop(:,k),vector0hop(:,k-2,istate))*t(i,l)*phase(k)+dummyHij(istate)
                        end do
                    end do
                end if
            end do
        end if
    end do
    
    if(myid==0) Hlr=0.0D0
    call MPI_REDUCE(dummyHij,Hlr,nstate,mpi_real8,MPI_SUM,0,MPI_COMM_WORLD,ierr)
    
    deallocate(vectorR,vectorL,vector0)
    deallocate(vectorRhop,vectorLhop,vector0hop)
    
    
    return
end subroutine GetHmat

!=============================================================================
!=============================================================================

subroutine PerturbationSpaceDvD(EIGS)
    use InitialGuess
    use ABop
    implicit none
    real(kind=r8),intent(inout) :: EIGS(:)
    ! local
    real(kind=r8),allocatable :: RES(:),eigenvector(:)
    integer ::        dimN         , &
                NEIG         , &  ! number of eigenstate
                MADSPACE     , &  ! subspace dimension
                iter         , &
                NINIT        , &  ! initial Guess
                Leigenvector , &
                isearch      , &
                info         , &
                iprint       , &
                ijob         , &
                ICNTL(5)     , &
                NDX1         , &
                NDX2         
    real(kind=r8) ::  Tol          , &
                sigma        , &
                shift        , &
                mem          , &
                droptol      , &
                gap
    integer :: error,ierr
    integer :: i,istate,ibasis
    real(kind=r8) :: starttime,endtime,overlap
    

!--------------------------------------------------------------------
    ! initial value
    NEIG=nstate
    MADSPACE=20
    iter=2000
    mem=20.0
    droptol=1.0D-3
    ICNTL(1)=0
    ICNTL(2)=0
    ICNTL(3)=0
    ICNTL(4)=0
    ICNTL(5)=0
    IPRINT=6
    NINIT=nstate
    dimN=ngoodstatesp
    Leigenvector=dimN*(3*MADSPACE+NEIG+1)+3*MADSPACE**2+MAX(MADSPACE**2,NEIG)+100

    if(myid==0) then
        allocate(RES(nstate))
        allocate(eigenvector(Leigenvector))
    else
        allocate(eigenvector(1))
    end if
    
    if(myid==0) then
        if(isweep/=0 .and. nelecs==realnelecs) then
            isearch=1
            sigma=EIGS(1)
            if(nstate/=1) then
                shift=EIGS(1)*2.0D0-EIGS(2)
            else 
                shift=EIGS(1)-1.0D0
            end if
        else
            isearch=0
            EIGS(1:nstate)=0.0D0
        end if
    end if
        
    if(isweep==0 .or. nelecs/=realnelecs) then
        Tol=5.0D-2
    else if(isweep==1) then
        Tol=5.0D-3
    else
        Tol=1.0D-4
    end if
!--------------------------------------------------------------------

    ! Get the Initialcoeff Guess
    if(myid==0) then
        ! call InitialStarter('i',dimN,NINIT,eigenvector)
        ! from the first order corrected wavefunction
        NINIT=nstate
        do istate=1,nstate,1
            call copy(coeffIFp(1:ngoodstatesp,istate),&
                eigenvector((istate-1)*ngoodstatesp+1:istate*ngoodstatesp))
        end do
    end if

    if(myid/=0) then  ! these parameter nouse in slaver process
        dimN=1
        NDX1=1
        NDX2=1
    endif
    if(myid==0) then
        write(*,*) "isweep=",isweep,"site=",nleft+1,norbs-nright
    end if
    IJOB=0
    do while(.true.)
        if(myid==0) then
            call DPJDREVCOM(dimN,HDIAGp,-1,-1,EIGS,RES,eigenvector,Leigenvector,NEIG,sigma,&
                isearch,NINIT,MADSPACE,ITER,TOL,SHIFT,DROPTOL,MEM,ICNTL,IJOB, &
                NDX1,NDX2,IPRINT,INFO,GAP)
        end if
        call MPI_BCAST(IJOB,1,MPI_integer,0,MPI_COMM_WORLD,ierr)
        if(IJOB/=1) then
            exit
        else
            if(opmethod=="comple") then
                call op(dimN,1,eigenvector(NDX1),eigenvector(NDX2),&
                    Lrealdimp,Rrealdimp,subMp,ngoodstatesp,&
                    operamatbig1p,bigcolindex1p,bigrowindex1p,&
                    Hbigp,Hbigcolindexp,Hbigrowindexp,&
                    quantabigLp,quantabigRp,goodbasisp,goodbasiscolp)
            else if(opmethod=="direct") then
                call opdirect(dimN,1,eigenvector(NDX1),eigenvector(NDX2),&
                    Lrealdimp,Rrealdimp,subMp,ngoodstatesp,&
                    operamatbig1p,bigcolindex1p,bigrowindex1p,&
                    Hbigp,Hbigcolindexp,Hbigrowindexp,&
                    quantabigLp,quantabigRp,goodbasisp,goodbasiscolp)
            else
                stop
            end if
        end if
    end do

    if(myid==0) then
        if(INFO/=0) then
            call master_print_message(info,"INFO/=0")
            stop
        end if
        write(*,*) "Perturbation space low state energy"
        do i=1,nstate,1
            write(*,*) nleft+1,norbs-nright,i,"th energy=",EIGS(i)
        end do
    end if
    
    if(myid==0) then
        ! in the perturbation space diagonalization update the coeffIFp
        write(*,*) "overlap with first order perturabtion wavefunction"
        do istate=1,nstate,1
            overlap = dot(eigenvector((istate-1)*ngoodstatesp+1:istate*ngoodstatesp),&
                coeffIFp(1:ngoodstatesp,istate))
           !overlap = dsdot(ngoodstatesp,eigenvector((istate-1)*ngoodstatesp+1:istate*ngoodstatesp),1,&
           !     coeffIFp(1:ngoodstatesp,istate),1)
            write(*,*) overlap
            call copy(eigenvector((istate-1)*ngoodstatesp+1:istate*ngoodstatesp),coeffIFp(:,istate))
        end do
        
        call DPJDCLEANUP
        deallocate(RES)
    end if
    deallocate(eigenvector)
    
    return
end subroutine PerturbationSpaceDvD

!=============================================================================
!=============================================================================

subroutine CorrectEOrder3(eigenvalue,num)
    use ABop
    implicit none
    integer,intent(in) :: num
    real(kind=r8),intent(in) :: eigenvalue(:)
    
    ! local 
    real(kind=r8),allocatable :: H0k(:,:),H0kout(:,:),midmat(:)
    integer :: istate,ibasis
    integer :: remainder

    call master_print_message("enter CorrectEOrder3 subroutine")

    if(myid==0) then
        allocate(H0k(ngoodstatesp,nstate))
        allocate(H0kout(ngoodstatesp,nstate))
        H0k=0.0D0
        H0kout=0.0D0

        do ibasis=1,ngoodstatesp,1       
            remainder=mod(goodbasisp(ibasis,1),Lrealdimp)
            if(remainder==0) remainder=Lrealdimp
            if(goodbasisp(ibasis,2)<=4*Rrealdim .and. remainder<=Lrealdim) then
                cycle
            else
                do istate=1,nstate,1
                    H0k(ibasis,istate)=H0lr(ibasis,istate)/(eigenvalue(istate)-Hdiagp(ibasis))
                end do
            end if
        end do
    end if
    
    ! calculate A=Hji'*(H0k'/E0k)
    if(opmethod=="comple") then
        call op(ngoodstatesp,nstate,H0k,H0kout,&
                Lrealdimp,Rrealdimp,subMp,ngoodstatesp,&
                operamatbig1p,bigcolindex1p,bigrowindex1p,&
                Hbigp,Hbigcolindexp,Hbigrowindexp,&
                quantabigLp,quantabigRp,goodbasisp,goodbasiscolp)
    else if(opmethod=="direct") then
        call opdirect(ngoodstatesp,nstate,H0k,H0kout,&
                Lrealdimp,Rrealdimp,subMp,ngoodstatesp,&
                operamatbig1p,bigcolindex1p,bigrowindex1p,&
                Hbigp,Hbigcolindexp,Hbigrowindexp,&
                quantabigLp,quantabigRp,goodbasisp,goodbasiscolp)
    else
        stop
    end if
            
    if(myid==0) then
        allocate(midmat(ngoodstatesp))
        do istate=1,nstate,1
            ! matrix operation
            midmat=Hdiagp*H0k(:,istate)
            H0kout(:,istate)=H0kout(:,istate)-midmat
        end do
        deallocate(midmat)
        ! calculate (H0j'/E0j)*A
        do istate=1,nstate,1
            correctenergy3(istate)=dot(H0k(:,istate),H0kout(:,istate))
        end do
    end if
    
    if(myid==0) then
        deallocate(H0k)
        deallocate(H0kout)
    end if

    return
end subroutine CorrectEOrder3

!================================================================
!================================================================

end module perturbation_mod
