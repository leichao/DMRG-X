Subroutine system_bigL
! construct the L+sigmaL subspace operator matrix in 4M basis
	
	use variables
	use mpi
	use mathlib
	use communicate

	implicit none
	
	integer :: operaindex,error,i,j,k,l,idummy,ierr
	real(kind=r8),allocatable :: Hbuffer(:,:),operabuffer(:,:,:)
	integer :: status(MPI_STATUS_SIZE)
	real(kind=r8) :: II(4,4),Im(subM,subM)
	integer(kind=i4),allocatable :: phase(:,:)
	
	

	if(myid==0) then
		write(*,*) "enter in subroutine system_bigL"
	end if
	
	allocate(phase(4*subM,4*subM),stat=error)
	if(error/=0) stop

	! construct the unit matrix
	II=0.0D0
	do i=1,4,1
		II(i,i)=1.0D0
	end do
	Im=0.0D0
	do i=1,subM,1
		Im(i,i)=1.0D0
	end do

	
! construct the L subspace operator matrix in 4M basis
	do i=1,nleft,1
	if(myid==orbid(i)) then
		if(mod(i,nprocs-1)==0) then
			operaindex=i/(nprocs-1)
		else
			operaindex=i/(nprocs-1)+1
		end if
		
		if(bondlink(i,nleft+1)==1) then
			call MPI_SEND(operamatsma(1,1,3*(operaindex-1)+1),3*subM*subM,mpi_real8,0,i,MPI_COMM_WORLD,ierr)
		else
			call MPI_SEND(operamatsma(1,1,3*operaindex),subM*subM,mpi_real8,0,i,MPI_COMM_WORLD,ierr)
		end if

		do j=1,3,1
			call directproduct(operamatsma(1:Lrealdim,1:Lrealdim,3*(operaindex-1)+j),Lrealdim,II,4,operamatbig(1:Lrealdim*4,1:Lrealdim*4,3*(operaindex-1)+j))
		end do
	end if
	end do


! construct the sigmaL subspace operator matrix in 4M basis
	if(myid==orbid(nleft+1)) then
		if(mod(nleft+1,nprocs-1)==0) then
			operaindex=(nleft+1)/(nprocs-1)
		else
			operaindex=(nleft+1)/(nprocs-1)+1
		end if
		
		do i=1,3,1
		if(i<=2) then
			do j=1,4*Lrealdim,1
				if(mod(j,Lrealdim)==0) then
					k=Lrealdim
				else
					k=mod(j,Lrealdim)
				end if
				phase(:,j)=(-1)**(mod(quantasmaL(k,1),2))
			end do
			call directproduct(Im(1:Lrealdim,1:Lrealdim),Lrealdim,onesitemat(:,:,i),4,operamatbig(1:Lrealdim*4,1:Lrealdim*4,3*(operaindex-1)+i),phase(1:Lrealdim*4,1:Lrealdim*4))
		else
			call directproduct(Im(1:Lrealdim,1:Lrealdim),Lrealdim,onesitemat(:,:,i),4,operamatbig(1:Lrealdim*4,1:Lrealdim*4,3*(operaindex-1)+i))
		end if
		end do
	end if

! cosntruct the L+sigmaL Hamiltonian operator in 4M basis
	if(myid==0) then
		allocate(Hbuffer(4*subM,4*subM),stat=error)
		if(error/=0) stop
		
!     L Hamiltonian contribute
		Hbig(:,:,1)=0.0D0
		call directproduct(Hsma(1:Lrealdim,1:Lrealdim,1),Lrealdim,II,4,Hbuffer(1:4*Lrealdim,1:4*Lrealdim))
		Hbig(1:4*Lrealdim,1:4*Lrealdim,1)=Hbuffer(1:4*Lrealdim,1:4*Lrealdim)
!-------------------------------------------------------
!     L sigmaL interaction operator contribute
		allocate(operabuffer(subM,subM,3),stat=error)
		if(error/=0) stop

		do i=1,nleft,1
			if(bondlink(nleft+1,i)==1) then
				call MPI_RECV(operabuffer(1,1,1),3*subM*subM,mpi_real8,orbid(i),i,MPI_COMM_WORLD,status,ierr)
			else
				call MPI_RECV(operabuffer(1,1,3),subM*subM,mpi_real8,orbid(i),i,MPI_COMM_WORLD,status,ierr)
			end if
			
			!transfer integral term
			if(bondlink(i,nleft+1)==1) then
			do j=1,2,1
				Hbuffer=0.0D0
				do k=1,4*Lrealdim,1
					if(mod(k,Lrealdim)==0) then
						l=Lrealdim
					else
						l=mod(k,Lrealdim)
					end if
					phase(:,k)=(-1)**(mod(quantasmaL(l,1),2))
				end do
				call directproduct(operabuffer(1:Lrealdim,1:Lrealdim,j),Lrealdim,onesitemat(:,:,3+j),&
				4,Hbuffer(1:4*Lrealdim,1:4*Lrealdim),phase(1:4*Lrealdim,1:4*Lrealdim))
				Hbig(1:4*Lrealdim,1:4*Lrealdim,1)=Hbig(1:4*Lrealdim,1:4*Lrealdim,1)+&
						(Hbuffer(1:4*Lrealdim,1:4*Lrealdim)+transpose(Hbuffer(1:4*Lrealdim,1:4*Lrealdim)))*t(i,nleft+1)
			end do
			end if
			!     ppp term
				Hbuffer=0.0D0
				call directproduct(operabuffer(1:Lrealdim,1:Lrealdim,3),Lrealdim,onesitemat(:,:,3),&
				4,Hbuffer(1:4*Lrealdim,1:4*Lrealdim))
				Hbig(1:4*Lrealdim,1:4*Lrealdim,1)=Hbig(1:4*Lrealdim,1:4*Lrealdim,1)+&
					Hbuffer(1:4*Lrealdim,1:4*Lrealdim)*pppV(i,nleft+1)
		end do
!--------------------------------------------------------------
!     sigmaL Hamiltonian contribute. site energy+HubbardU
		Hbuffer=0.0D0
		do i=1,Lrealdim,1
			Hbuffer(1*Lrealdim+i,1*Lrealdim+i)=t(nleft+1,nleft+1)
			Hbuffer(2*Lrealdim+i,2*Lrealdim+i)=t(nleft+1,nleft+1)
			Hbuffer(3*Lrealdim+i,3*Lrealdim+i)=t(nleft+1,nleft+1)*2.0D0+hubbardU(nleft+1)
		end do
		Hbig(1:4*Lrealdim,1:4*Lrealdim,1)=Hbuffer(1:4*Lrealdim,1:4*Lrealdim)+Hbig(1:4*Lrealdim,1:4*Lrealdim,1)
!-------------------------------------------------------------------

		if(logic_spinreversal/=0) then
			symmlinkbig(1:Lrealdim,1,1)=symmlinksma(1:Lrealdim,1,1)
			symmlinkbig(Lrealdim+1:2*Lrealdim,1,1)=(abs(symmlinksma(1:Lrealdim,1,1))+2*&
				Lrealdim)*sign(1,symmlinksma(1:Lrealdim,1,1))
			symmlinkbig(2*Lrealdim+1:3*Lrealdim,1,1)=(abs(symmlinksma(1:Lrealdim,1,1))+&
				Lrealdim)*sign(1,symmlinksma(1:Lrealdim,1,1))
			symmlinkbig(3*Lrealdim+1:4*Lrealdim,1,1)=(abs(symmlinksma(1:Lrealdim,1,1))+3*&
				Lrealdim)*sign(1,symmlinksma(1:Lrealdim,1,1))*(-1)
		end if

	deallocate(Hbuffer)
	deallocate(operabuffer)
	end if
	
	deallocate(phase)
	return
end subroutine system_bigL

