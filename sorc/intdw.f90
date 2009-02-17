subroutine intdw(ru,rv,su,sv,dru,drv,dsu,dsv)
!$$$  subprogram documentation block
!                .      .    .                                       .
! subprogram:    intw        apply nonlin qc operator for lidar winds
!   prgmmr: derber           org: np23                date: 1991-02-26
!
! abstract: apply observation operator and adjoint for lidar winds
!             with nonlinear qc operator
!
! program history log:
!   1991-02-26  derber
!   1999-11-22  yang
!   2004-08-02  treadon - add only to module use, add intent in/out
!   2004-10-07  parrish - add nonlinear qc option
!   2005-03-01  parrish - nonlinear qc change to account for inflated obs error
!   2005-04-11  treadon - merge intdw and intdw_qc into single routine
!   2005-08-02  derber  - modify for variational qc parameters for each ob
!   2005-09-28  derber  - consolidate location and weight arrays
!   2006-07-28  derber  - modify to use new inner loop obs data structure
!                       - unify NL qc
!   2007-02-15  rancic - add foto
!
! usage: call intdw(ru,rv,su,sv)
!   input argument list:
!     su       - u increment in grid space
!     sv       - v increment in grid space
!     dsu      - time derivative of u increment in grid space
!     dsv      - time derivative of v increment in grid space
!
!   output argument list:
!     ru       - output u adjoint operator results 
!     rv       - output v adjoint operator results 
!     dru      - output time derivative of u adjoint operator results 
!     drv      - output time derivative of v adjoint operator results 
!
! attributes:
!   language: f90
!   machine:  ibm RS/6000 SP
!
!$$$
  use kinds, only: r_kind,i_kind
  use constants, only: half,one,two,zero,tiny_r_kind,cg_term
  use obsmod, only: dwhead,dwptr
  use qcmod, only: nlnqc_iter
  use gridmod, only: latlon1n
  implicit none

! Declare passed variables
  real(r_kind),dimension(latlon1n),intent(in):: su,sv,dsu,dsv
  real(r_kind),dimension(latlon1n),intent(inout):: ru,rv,dru,drv

! Declare local variables
  integer(i_kind) i,j1,j2,j3,j4,j5,j6,j7,j8
! real(r_kind) penalty
  real(r_kind) val,valu,valv,w1,w2,w3,w4,w5,w6,w7,w8
  real(r_kind) cg_dw,p0,grad,wnotgross,wgross,time_dwi


  dwptr => dwhead
  do while (associated(dwptr))
     j1=dwptr%ij(1)
     j2=dwptr%ij(2)
     j3=dwptr%ij(3)
     j4=dwptr%ij(4)
     j5=dwptr%ij(5)
     j6=dwptr%ij(6)
     j7=dwptr%ij(7)
     j8=dwptr%ij(8)
     w1=dwptr%wij(1)
     w2=dwptr%wij(2)
     w3=dwptr%wij(3)
     w4=dwptr%wij(4)
     w5=dwptr%wij(5)
     w6=dwptr%wij(6)
     w7=dwptr%wij(7)
     w8=dwptr%wij(8)
     
     time_dwi=dwptr%time
!    Forward model
     val=(w1*su(j1)+w2*su(j2)+w3*su(j3)+w4*su(j4)+                   &
          w5*su(j5)+w6*su(j6)+w7*su(j7)+w8*su(j8))*dwptr%sinazm+  &
         (w1*sv(j1)+w2*sv(j2)+w3*sv(j3)+w4*sv(j4)+                   &
          w5*sv(j5)+w6*sv(j6)+w7*sv(j7)+w8*sv(j8))*dwptr%cosazm   &
          -dwptr%res
     val=((w1*dsu(j1)+w2*dsu(j2)+w3*dsu(j3)+w4*dsu(j4)+                &
           w5*dsu(j5)+w6*dsu(j6)+w7*dsu(j7)+w8*dsu(j8))*dwptr%sinazm+  &
          (w1*dsv(j1)+w2*dsv(j2)+w3*dsv(j3)+w4*dsv(j4)+                &
           w5*dsv(j5)+w6*dsv(j6)+w7*dsv(j7)+w8*dsv(j8))*dwptr%cosazm)  &
           *time_dwi+val

!    gradient of nonlinear operator
     if (nlnqc_iter .and. dwptr%pg > tiny_r_kind .and. &
                          dwptr%b  > tiny_r_kind) then
        cg_dw=cg_term/dwptr%b
        wnotgross= one-dwptr%pg
        wgross = dwptr%pg*cg_dw/wnotgross
        p0   = wgross/(wgross+exp(-half*dwptr%err2*val**2))
        val = val*(one-p0)
     endif

     grad     = val * dwptr%raterr2 * dwptr%err2

!    Adjoint
     valu=dwptr%sinazm * grad
     valv=dwptr%cosazm * grad
     ru(j1)=ru(j1)+w1*valu
     ru(j2)=ru(j2)+w2*valu
     ru(j3)=ru(j3)+w3*valu
     ru(j4)=ru(j4)+w4*valu
     ru(j5)=ru(j5)+w5*valu
     ru(j6)=ru(j6)+w6*valu
     ru(j7)=ru(j7)+w7*valu
     ru(j8)=ru(j8)+w8*valu
     rv(j1)=rv(j1)+w1*valv
     rv(j2)=rv(j2)+w2*valv
     rv(j3)=rv(j3)+w3*valv
     rv(j4)=rv(j4)+w4*valv
     rv(j5)=rv(j5)+w5*valv
     rv(j6)=rv(j6)+w6*valv
     rv(j7)=rv(j7)+w7*valv
     rv(j8)=rv(j8)+w8*valv
     valu = valu*time_dwi
     valv = valv*time_dwi
     dru(j1)=dru(j1)+w1*valu
     dru(j2)=dru(j2)+w2*valu
     dru(j3)=dru(j3)+w3*valu
     dru(j4)=dru(j4)+w4*valu
     dru(j5)=dru(j5)+w5*valu
     dru(j6)=dru(j6)+w6*valu
     dru(j7)=dru(j7)+w7*valu
     dru(j8)=dru(j8)+w8*valu
     drv(j1)=drv(j1)+w1*valv
     drv(j2)=drv(j2)+w2*valv
     drv(j3)=drv(j3)+w3*valv
     drv(j4)=drv(j4)+w4*valv
     drv(j5)=drv(j5)+w5*valv
     drv(j6)=drv(j6)+w6*valv
     drv(j7)=drv(j7)+w7*valv
     drv(j8)=drv(j8)+w8*valv

     dwptr => dwptr%llpoint

  end do
  return
end subroutine intdw
