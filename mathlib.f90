module MathLib
	
	use kinds_mod
	use blas95
	use f95_precision

	implicit none
	contains
!=============================================================================
Subroutine DirectProduct(a,dima,b,dimb,c)
! this subroutine is to do direct product of two matrix
! for example :<sigmaL|<L|O|L>|sigmaL>
! a is the L matrix, b is the sigmaL matrix

implicit none

integer(kind=i4) :: dima,dimb
real(kind=r8) ::a(dima,dima),b(dimb,dimb),c(dima*dimb,dima*dimb)
integer :: iar,ial,ibr,ibl

c=0.0D0
do ibr=1,dimb,1
do iar=1,dima,1
	do ibl=1,dimb,1
	do ial=1,dima,1
		c((ibl-1)*dima+ial,(ibr-1)*dima+iar)=a(ial,iar)*b(ibl,ibr)
	end do
	end do
end do
end do

return
end Subroutine DirectProduct

!===============================================

subroutine GramSchmit(nvector,lvector,vectorwork,normwork)
! Gram-Schmit Orthogonalization subroutine

! input - nvector :: the number of vectors
! input - lvector :: the length of every vector
! input - vectorwork :: the workmemory of vectors
! output - normwork :: the norm of every vector after orthogonalization


	implicit none
	integer :: nvector,lvector
	real(kind=r8) :: vectorwork(lvector*nvector),normwork(nvector)&
	,overlap
	integer ::  i,j
	
	do i=1,nvector,1
		do j=1,i-1,1
			overlap=dot(vectorwork((i-1)*lvector+1:i*lvector),&
				vectorwork((j-1)*lvector+1:j*lvector))

			vectorwork((i-1)*lvector+1:i*lvector)=&
				vectorwork((i-1)*lvector+1:i*lvector)-&
				overlap*vectorwork((j-1)*lvector+1:j*lvector)
		end do
			normwork(i)=dot(vectorwork((i-1)*lvector+1:i*lvector),&
				vectorwork((i-1)*lvector+1:i*lvector))
			if(normwork(i)<1.0D-10) then
				write(*,*) "--------------------------"
				write(*,*) "norm is < 1.0D-10,caution!",i,"th state"
				write(*,*) "--------------------------"
			end if
			vectorwork((i-1)*lvector+1:i*lvector)=&
				vectorwork((i-1)*lvector+1:i*lvector)/sqrt(normwork(i))
	end do
	return

end subroutine GramSchmit

!=============================================

subroutine ScaleMatrix(mat,rows,cols,scaling,op)
! this subroutine use mkl mkl_?imatcopy to do scaling a matrix

	implicit none
	include "mkl.fi"

	integer :: rows,cols
	real(kind=r8) :: mat(rows,cols),scaling
	character(len=1) :: op
	integer :: src_lda,dst_lda
	
	src_lda=rows
	if(op=='T' .or. op=='t' .or. op=='C' .or. op=='c') then
		dst_lda=cols
	else if(op=='N' .or. op=='n' .or. op=='R' .or. op=='r') then
		dst_lda=rows
	end if

	call mkl_dimatcopy('C',op,rows,cols,scaling,mat,src_lda,dst_lda)

return
end subroutine  ScaleMatrix

!=============================================
!=============================================

subroutine Diagsyev(dim1,mat,eigenvalue,eigenvector)
	use lapack95
	use f95_precision
	implicit none
	
	integer :: dim1
	real(kind=r8) :: mat(dim1,dim1),eigenvalue(dim1),eigenvector(dim1,dim1)

	call syevr(mat,eigenvalue,'U',eigenvector)

return

end subroutine diagsyev

!=============================================
end module MathLib
