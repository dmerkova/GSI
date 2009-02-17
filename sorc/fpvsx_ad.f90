subroutine fpvsx_ad( t, es, t_ad, es_ad, adjoint )
!$$$  subprogram documentation block
!                .      .    .                                       .
! subprogram:    fpvsx_ad     forward and adjoint model for saturation vapor pressure
!     prgmmr:    treadon     org: np23                date: 2003-12-18
!
! abstract:  This subroutine contains the forward and ajoint models for the
!            calculation of saturation vapor pressure.  
!
! program history log:
!   03-12-18  treadon - initial routine
!   04-06-14  treadon - reformat documenation
!
!   input argument list:
!     t       - temperature
!     es_ad    - vapor pressure perturbation
!     adjoint - logical flag (.false.=forward model only, .true.=forward and ajoint)
!
!   output argument list:
!     t_ad      - partial derivative of vapor pressure with respect to temperature 
!
! remarks:
!    The adjoint portion of this routine was generated by the 
!    Tangent linear and Adjoint Model Compiler,  TAMC 5.3.0
!
! attributes:
!   language: f90
!   machine:  ibm RS/6000 SP
!
!$$$
!==============================================
! all entries are defined explicitly
!==============================================
  use kinds, only: r_kind
  use constants, only: zero, one, tmix, xai, xbi, xa, xb, ttp, psatk
  implicit none

!==============================================
! define arguments
!==============================================
  logical adjoint
  real(r_kind) es_ad
  real(r_kind) t_ad
  real(r_kind) es
  real(r_kind) t

!==============================================
! define local variables
!==============================================
  real(r_kind) tr_ad
  real(r_kind) w_ad
  real(r_kind) tr
  real(r_kind) w

!----------------------------------------------
! RESET LOCAL ADJOINT VARIABLES
!----------------------------------------------
  tr_ad = zero
  w_ad = zero

!----------------------------------------------
! ROUTINE BODY
!----------------------------------------------
!----------------------------------------------
! FUNCTION AND TAPE COMPUTATIONS
!----------------------------------------------
  tr = ttp/t
  if (t .ge. ttp) then
     es = psatk*tr**xa*exp(xb*(one-tr))
  else if (t .lt. tmix) then
     es = psatk*tr**xai*exp(xbi*(one-tr))
  else
     w = (t-tmix)/(ttp-tmix)
     es = w*psatk*tr**xa*exp(xb*(one-tr))+(one-w)*psatk*tr**xai* &
          exp(xbi*(one-tr))
  endif
  
  if (.not.adjoint) return

!----------------------------------------------
! ADJOINT COMPUTATIONS
!----------------------------------------------
  if (t .ge. ttp) then
     tr_ad = tr_ad+es_ad*((-(psatk*tr**xa*xb*exp(xb*(one-tr))))+psatk*xa* &
          tr**(xa-1)*exp(xb*(one-tr)))
     es_ad = zero
  else if (t .lt. tmix) then
     tr_ad = tr_ad+es_ad*((-(psatk*tr**xai*xbi*exp(xbi*(one-tr))))+psatk* &
          xai*tr**(xai-1)*exp(xbi*(one-tr)))
     es_ad = zero
  else
     tr_ad = tr_ad+es_ad*((-(w*psatk*tr**xa*xb*exp(xb*(one-tr))))+w* &
          psatk*xa*tr**(xa-1)*exp(xb*(one-tr))-(one-w)*psatk*tr**xai*xbi* &
          exp(xbi*(one-tr))+(one-w)*psatk*xai*tr**(xai-1)*exp(xbi*(one-tr)))
     w_ad = w_ad+es_ad*(psatk*tr**xa*exp(xb*(one-tr))-psatk*tr**xai* &
          exp(xbi*(one-tr)))
     es_ad = zero
     t_ad = t_ad+w_ad/(ttp-tmix)
     w_ad = zero
  endif
  t_ad = t_ad-tr_ad*(ttp/(t*t))
  tr_ad = zero
  
  return
end subroutine fpvsx_ad


