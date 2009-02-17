module mod_inmi
!$$$   module documentation block
!                .      .    .                                       .
! module:  obsmod
! prgmmr:  derber             org: np23               date: 2003-09-25
!
! abstract: Implement implicit normal mod initialization routines for
!           use with analysis increment and analysis increment tendencies.
!        reference: Temperton, C., 1989:  "Implicit Normal Mode Initialization
!                           for Spectral Models", .  MWR, 117, 436-451.
!
! program history log:
!   2006-08-15 parrish
!
! Subroutines Included:
!   sub init_strongvars_1- set default namelist variable values for strong option 1
!   sub gproj            - project input u,v,mass variable to gravity modes
!   sub dinmi            - obtain balance increment from input tendencies
!   sub dinmi_ad         - adjoint of dinmi
!   sub dinmi0           - lower level--balance increment from input tendencies
!   sub bal_m1           - compute balance diagnostic variable
!   sub get_periodmask   - create mask to only balance gravity modes with periods
!                          less than period_max
!   sub getbcf           - compute matrices B,C,F as defined in above reference
!   sub scale_vars       - scale variables as defined in reference
!   sub scale_vars_ad    - adjoint of scale variables
!   sub unscale_vars     - unscale variables
!   sub unscale_vars_ad  - adjoint of unscale variables
!   sub f_mult           - multiply by F matrix
!   sub c_mult           - multiply by C matrix
!   sub i_mult           - multiply by sqrt(-1)
!   sub solve_f2c2       - solve (F*F+C*C)*x = y
!
! attributes:
!   language: f90
!   machine:  ibm RS/6000 SP
!
!$$$ end documentation block

use kinds,only: r_kind,i_kind
implicit none

  integer(i_kind) mmax
  integer(i_kind) m
  real(r_kind) gspeed

contains

  subroutine gproj(vort,div,phi,vort_g,div_g,phi_g,rmstend,rmstend_g,filtered)

!      for gravity wave projection:    vort, div, phi --> vort_g, div_g, phi_g
!      -----------------------------------------------------------------------

!         scale:      vort,div,phi --> vort_hat,div_hat,phi_hat

!         solve:     (F*F+C*C)*x = F*vort_hat + C*phi_hat
!         then:
!               phi_hat_g = C*x
!              vort_hat_g = F*x
!               div_hat_g = div_hat

!         unscale:    vort_hat_g, div_hat_g, phi_hat_g --> vort_g, div_g, phi_g

    use kinds, only: r_kind,i_kind
    implicit none

    real(r_kind),intent(in)::vort(2,m:mmax),div(2,m:mmax),phi(2,m:mmax)
    real(r_kind),intent(out)::vort_g(2,m:mmax),div_g(2,m:mmax),phi_g(2,m:mmax)
    real(r_kind),intent(inout)::rmstend,rmstend_g
    logical,intent(in)::filtered

    real(r_kind) pmask(m:mmax)
    real(r_kind) vort_hat(2,m:mmax),div_hat(2,m:mmax),phi_hat(2,m:mmax)
    real(r_kind) vort_hat_g(2,m:mmax),div_hat_g(2,m:mmax),phi_hat_g(2,m:mmax)
    real(r_kind) rmstendnm(m:mmax)
    integer(i_kind) n

    call scale_vars(vort,div,phi,vort_hat,div_hat,phi_hat)
    if(filtered) then
      call get_periodmask(pmask)
      do n=m,mmax
        vort_hat(1,n)=pmask(n)*vort_hat(1,n)
        vort_hat(2,n)=pmask(n)*vort_hat(2,n)
        div_hat(1,n)=pmask(n)*div_hat(1,n)
        div_hat(2,n)=pmask(n)*div_hat(2,n)
        phi_hat(1,n)=pmask(n)*phi_hat(1,n)
        phi_hat(2,n)=pmask(n)*phi_hat(2,n)
      end do
    end if
    call balm_1(vort_hat,div_hat,phi_hat,rmstendnm)
    do n=m,mmax
      rmstend=rmstend+rmstendnm(n)
    end do

    call gproj0(vort_hat,div_hat,phi_hat,vort_hat_g,div_hat_g,phi_hat_g)
    call balm_1(vort_hat_g,div_hat_g,phi_hat_g,rmstendnm)
    do n=m,mmax
      rmstend_g=rmstend_g+rmstendnm(n)
    end do

    call unscale_vars(vort_hat_g,div_hat_g,phi_hat_g,vort_g,div_g,phi_g)

  end subroutine gproj

  subroutine gproj0(vort_hat,div_hat,phi_hat,vort_hat_g,div_hat_g,phi_hat_g)

!  for gravity wave projection: vort,div,phi --> vort_g,div_g,phi_g
!  -----------------------------------------------------------------------------


!    solve:  (F*F+C*C)*x = F*vort_hat + C*phi_hat

!    then:
!          phi_hat_g  = C*x
!         vort_hat_g  = F*x
!          div_hat_g  = div_hat

    use kinds, only: r_kind,i_kind
    implicit none

    real(r_kind),dimension(2,m:mmax),intent(in):: vort_hat,div_hat,phi_hat
    real(r_kind),dimension(2,m:mmax),intent(out):: vort_hat_g,div_hat_g,phi_hat_g

    real(r_kind) b(m:mmax),c(m:mmax),f(m:mmax)
    real(r_kind) x(2,m:mmax),y(2,m:mmax)

    call getbcf(b,c,f)

    call f_mult(y,vort_hat,f)
    call c_mult(x,phi_hat,c)
    y=y+x
    call solve_f2c2(x,y,f,c)
    call c_mult(phi_hat_g,x,c)
    call f_mult(vort_hat_g,x,f)
    div_hat_g=div_hat

  end subroutine gproj0

  subroutine gproj_ad(vort,div,phi,vort_g,div_g,phi_g)

!  for gravity wave projection: vort,div,phi --> vort_g,div_g,phi_g
!  -----------------------------------------------------------------------------


!    scale:      vort,div,phi --> vort_hat,div_hat,phi_hat

!    solve:  (F*F+C*C)*x = F*vort_hat + C*phi_hat

!    then:
!               phi_hat_g = C*x
!              vort_hat_g = F*x
!               div_hat_g = div_hat

!         unscale:    vort_hat_g, div_hat_g, phi_hat_g --> vort_g, div_g, phi_g

    use kinds, only: r_kind,i_kind
    use constants, only: zero
    implicit none

    real(r_kind),intent(inout)::vort(2,m:mmax),div(2,m:mmax),phi(2,m:mmax)
    real(r_kind),intent(in)::vort_g(2,m:mmax),div_g(2,m:mmax),phi_g(2,m:mmax)

    real(r_kind) pmask(m:mmax)
    real(r_kind) vort_hat(2,m:mmax),div_hat(2,m:mmax),phi_hat(2,m:mmax)
    real(r_kind) vort_hat_g(2,m:mmax),div_hat_g(2,m:mmax),phi_hat_g(2,m:mmax)
    integer(i_kind) n

    vort_hat_g=zero
    div_hat_g=zero
    phi_hat_g=zero
    call unscale_vars_ad(vort_hat_g,div_hat_g,phi_hat_g,vort_g,div_g,phi_g)
    call gproj0(vort_hat_g,div_hat_g,phi_hat_g,vort_hat,div_hat,phi_hat)
    call get_periodmask(pmask)
    do n=m,mmax
      vort_hat(1,n)=pmask(n)*vort_hat(1,n)
      vort_hat(2,n)=pmask(n)*vort_hat(2,n)
      div_hat(1,n)=pmask(n)*div_hat(1,n)
      div_hat(2,n)=pmask(n)*div_hat(2,n)
      phi_hat(1,n)=pmask(n)*phi_hat(1,n)
      phi_hat(2,n)=pmask(n)*phi_hat(2,n)
    end do
    call scale_vars_ad(vort,div,phi,vort_hat,div_hat,phi_hat)

  end subroutine gproj_ad

  subroutine dinmi(vort_t,div_t,phi_t,del_vort,del_div,del_phi)

!  for implicit nmi correction: vort_t,div_t,phi_t --> del_vort,del_div,del_phi
!  -----------------------------------------------------------------------------


!    scale:      vort_t,div_t,phi_t --> vort_t_hat,div_t_hat,phi_t_hat

!    solve:  (F*F+C*C)*del_div_hat = sqrt(-1)*(F*vort_t_hat + C*phi_t_hat)

!    solve:  (F*F+C*C)*x = sqrt(-1)*div_t_hat - B*del_div_hat

!    then:
!          del_phi_hat  = C*x
!          del_vort_hat = F*x

!    unscale: del_vort_hat,del_div_hat,del_phi_hat --> del_vort,del_div,del_phi

    use kinds, only: r_kind,i_kind
    implicit none

    real(r_kind),intent(in)::vort_t(2,m:mmax),div_t(2,m:mmax),phi_t(2,m:mmax)
    real(r_kind),intent(out)::del_vort(2,m:mmax),del_div(2,m:mmax),del_phi(2,m:mmax)

    real(r_kind) pmask(m:mmax)
    real(r_kind) vort_t_hat(2,m:mmax),div_t_hat(2,m:mmax),phi_t_hat(2,m:mmax)
    real(r_kind) del_vort_hat(2,m:mmax),del_div_hat(2,m:mmax),del_phi_hat(2,m:mmax)
    integer(i_kind) n

    call scale_vars(vort_t,div_t,phi_t,vort_t_hat,div_t_hat,phi_t_hat)
    call get_periodmask(pmask)
    do n=m,mmax
      vort_t_hat(1,n)=pmask(n)*vort_t_hat(1,n)
      vort_t_hat(2,n)=pmask(n)*vort_t_hat(2,n)
      div_t_hat(1,n)=pmask(n)*div_t_hat(1,n)
      div_t_hat(2,n)=pmask(n)*div_t_hat(2,n)
      phi_t_hat(1,n)=pmask(n)*phi_t_hat(1,n)
      phi_t_hat(2,n)=pmask(n)*phi_t_hat(2,n)
    end do
    call dinmi0(vort_t_hat,div_t_hat,phi_t_hat,del_vort_hat,del_div_hat,del_phi_hat)

    call unscale_vars(del_vort_hat,del_div_hat,del_phi_hat,del_vort,del_div,del_phi)

  end subroutine dinmi

  subroutine dinmi_ad(vort_t,div_t,phi_t,del_vort,del_div,del_phi)

!  for implicit nmi correction: vort_t,div_t,phi_t --> del_vort,del_div,del_phi
!  -----------------------------------------------------------------------------


!    scale:      vort_t,div_t,phi_t --> vort_t_hat,div_t_hat,phi_t_hat

!    solve:  (F*F+C*C)*del_div_hat = sqrt(-1)*(F*vort_t_hat + C*phi_t_hat)

!    solve:  (F*F+C*C)*x = sqrt(-1)*div_t_hat - B*del_div_hat

!    then:
!          del_phi_hat  = C*x
!          del_vort_hat = F*x

!    unscale: del_vort_hat,del_div_hat,del_phi_hat --> del_vort,del_div,del_phi

    use kinds, only: r_kind,i_kind
    implicit none

    real(r_kind),intent(inout)::vort_t(2,m:mmax),div_t(2,m:mmax),phi_t(2,m:mmax)
    real(r_kind),intent(in)::del_vort(2,m:mmax),del_div(2,m:mmax),del_phi(2,m:mmax)

    real(r_kind) pmask(m:mmax)
    real(r_kind) vort_t_hat(2,m:mmax),div_t_hat(2,m:mmax),phi_t_hat(2,m:mmax)
    real(r_kind) del_vort_hat(2,m:mmax),del_div_hat(2,m:mmax),del_phi_hat(2,m:mmax)
    integer(i_kind) n

    del_vort_hat=0 ; del_div_hat=0 ; del_phi_hat=0
    call unscale_vars_ad(del_vort_hat,del_div_hat,del_phi_hat,del_vort,del_div,del_phi)
    call dinmi0(del_vort_hat,del_div_hat,del_phi_hat,vort_t_hat,div_t_hat,phi_t_hat)
    call get_periodmask(pmask)
    do n=m,mmax
      vort_t_hat(1,n)=-pmask(n)*vort_t_hat(1,n)
      vort_t_hat(2,n)=-pmask(n)*vort_t_hat(2,n)
      div_t_hat(1,n)=-pmask(n)*div_t_hat(1,n)
      div_t_hat(2,n)=-pmask(n)*div_t_hat(2,n)
      phi_t_hat(1,n)=-pmask(n)*phi_t_hat(1,n)
      phi_t_hat(2,n)=-pmask(n)*phi_t_hat(2,n)
    end do
    call scale_vars_ad(vort_t,div_t,phi_t,vort_t_hat,div_t_hat,phi_t_hat)

  end subroutine dinmi_ad

  subroutine dinmi0(vort_t_hat,div_t_hat,phi_t_hat,del_vort_hat,del_div_hat,del_phi_hat)

!  for implicit nmi correction: vort_t,div_t,phi_t --> del_vort,del_div,del_phi
!  -----------------------------------------------------------------------------


!    solve:  (F*F+C*C)*del_div_hat = sqrt(-1)*(F*vort_t_hat + C*phi_t_hat)

!    solve:  (F*F+C*C)*x = sqrt(-1)*div_t_hat - B*del_div_hat

!    then:
!          del_phi_hat  = C*x
!          del_vort_hat = F*x

    use kinds, only: r_kind,i_kind
    implicit none

    real(r_kind),dimension(2,m:mmax),intent(in):: vort_t_hat,div_t_hat,phi_t_hat
    real(r_kind),dimension(2,m:mmax),intent(out):: del_vort_hat,del_div_hat,del_phi_hat

    real(r_kind) b(m:mmax),c(m:mmax),f(m:mmax)
    real(r_kind) x(2,m:mmax),y(2,m:mmax)

    call getbcf(b,c,f)

    call f_mult(y,vort_t_hat,f)
    call c_mult(x,phi_t_hat,c)
    x=y+x
    call i_mult(y,x)
    call solve_f2c2(del_div_hat,y,f,c)
    call c_mult(x,del_div_hat,b)       !  actually multiplying by b
    call i_mult(y,div_t_hat)
    y=y-x
    call solve_f2c2(x,y,f,c)
    call c_mult(del_phi_hat,x,c)
    call f_mult(del_vort_hat,x,f)

  end subroutine dinmi0

  subroutine balm_1(vort_t_hat,div_t_hat,phi_t_hat,balnm1)

!  obtain balance diagnostic for each wave number n,m using method 1 (eq 4.23 of Temperton,1989)
!  -----------------------------------------------------------------------------

!            balnm1 = abs(vort_t_hat)(n,m)**2 + abs(div_t_hat)(n,m)**2 + abs(phi_t_hat)(n,m)**2

    use kinds, only: r_kind,i_kind
    implicit none

    real(r_kind),intent(in)::vort_t_hat(2,m:mmax),div_t_hat(2,m:mmax),phi_t_hat(2,m:mmax)
    real(r_kind),intent(out)::balnm1(m:mmax)

    integer(i_kind) n

    do n=m,mmax
      balnm1(n)=vort_t_hat(1,n)**2+vort_t_hat(2,n)**2 &
               +div_t_hat(1,n)**2+div_t_hat(2,n)**2 &
               +phi_t_hat(1,n)**2+phi_t_hat(2,n)**2
    end do

  end subroutine balm_1

  subroutine get_periodmask(pmask)

!     create mask to zero out components with estimated periods longer than period_max, where
!          period_max is in hours

!         c = phase speed for given vertical mode

!         L/c = period, where L is wavelength

!        L = 2*pi*erad/n     where n is wavenumber and 2*pi*erad is circumference of earth

    use kinds, only: r_kind,i_kind
    use constants, only: zero,half,one,rearth
    use mod_strong, only: period_max,period_width
    implicit none

    real(r_kind),intent(out)::pmask(m:mmax)

    real(r_kind) pi,thislength,thisperiod
    integer(i_kind) n

    pi=4._8*atan(1._8)
    do n=m,mmax
      pmask(n)=zero
      if(n.eq.0) cycle
      thislength=2._8*pi*rearth/n
      thisperiod=thislength/(gspeed*3600._8)
      pmask(n)=half*(one-tanh((thisperiod-period_max)/period_width))
    end do

  end subroutine get_periodmask

  subroutine getbcf(b,c,f)

    use kinds, only: r_kind,i_kind
    use constants, only: zero,one,two,four,omega,rearth
    use mod_strong, only: scheme
    implicit none

!   compute operators needed to do gravity wave projection
!     and implicit normal mode initialization in spectral space

    real(r_kind),intent(out)::b(m:mmax),c(m:mmax),f(m:mmax)

    integer(i_kind) n,nstart
    real(r_kind) eps,rn,rm

!   scheme B:   b = 2*omega*m/(n*(n+1))
!               f = 2*omega*sqrt(n*n-1)*eps/n
!               c = gspeed*sqrt(n*(n+1))/erad

!   scheme C:   b = 0
!               f = 2*omega*sqrt(n*n-1)*eps/n
!               c = gspeed*sqrt(n*(n+1))/erad

!   scheme D:   b = 0
!               f = 2*omega*eps
!               c = gspeed*sqrt(n*(n+1))/erad

!     in the above, eps = sqrt((n*n-m*m)/(4*n*n-1))

    nstart=max(m,1)
    rm=m
    do n=nstart,mmax
      rn=n
      eps=sqrt((rn*rn-rm*rm )/(four*rn*rn-one))
      if(scheme.eq.'B') then
        b(n)=two*omega*rm/(rn*(rn+one))
        f(n)=two*omega*sqrt(rn*rn-one)*eps/rn
        c(n)=gspeed*sqrt(rn*(rn+one))/rearth
      else if(scheme.eq.'C') then
        b(n)=zero
        f(n)=two*omega*sqrt(rn*rn-one)*eps/rn
        c(n)=gspeed*sqrt(rn*(rn+one))/rearth
      else if(scheme.eq.'D') then
        b(n)=zero
        f(n)=two*omega*eps
        c(n)=gspeed*sqrt(rn*(rn+one))/rearth
      else
           write(6,*)' scheme = ',scheme,' incorrect, must be = B, C, or D'
      end if
    end do

  end subroutine getbcf

  subroutine scale_vars(vort,div,phi,vort_hat,div_hat,phi_hat)

!        input scaling:

!     for schemes B, C:

!           vort_hat(n) = erad*vort(n)/sqrt(n*(n+1))

!           div_hat(n)  = sqrt(-1)*erad*div(n)/sqrt(n*(n+1))

!           phi_hat(n)  = phi(n)/gspeed

!     for scheme D:

!           vort_hat(n) = erad*vort(n)

!           div_hat(n)  = sqrt(-1)*erad*div(n)

!           phi_hat(n)  = phi(n)*sqrt(n*(n+1))/gspeed

    use kinds, only: i_kind,r_kind
    use constants, only: zero,one,rearth
    use mod_strong, only: scheme
    implicit none

    real(r_kind),intent(in)::vort(2,m:mmax),div(2,m:mmax),phi(2,m:mmax)
    real(r_kind),intent(out)::vort_hat(2,m:mmax),div_hat(2,m:mmax),phi_hat(2,m:mmax)

    integer(i_kind) n,nstart

!   following is to account for 0,0 term being zero

    vort_hat(1,m)=zero
    vort_hat(2,m)=zero
    div_hat(1,m)=zero
    div_hat(2,m)=zero
    phi_hat(1,m)=zero
    phi_hat(2,m)=zero
    nstart=max(m,1)
    if(scheme.ne.'D') then
      do n=nstart,mmax
        vort_hat(1,n)=rearth*vort(1,n)/sqrt(n*(n+one))
        vort_hat(2,n)=rearth*vort(2,n)/sqrt(n*(n+one))
        div_hat(2,n)=rearth*div(1,n)/sqrt(n*(n+one))
        div_hat(1,n)=-rearth*div(2,n)/sqrt(n*(n+one))
        phi_hat(1,n)=phi(1,n)/gspeed
        phi_hat(2,n)=phi(2,n)/gspeed
      end do
    else
      do n=nstart,mmax
        vort_hat(1,n)=rearth*vort(1,n)
        vort_hat(2,n)=rearth*vort(2,n)
        div_hat(2,n)=rearth*div(1,n)
        div_hat(1,n)=-rearth*div(2,n)
        phi_hat(1,n)=sqrt(n*(n+one))*phi(1,n)/gspeed
        phi_hat(2,n)=sqrt(n*(n+one))*phi(2,n)/gspeed
      end do
    end if

  end subroutine scale_vars

  subroutine scale_vars_ad(vort,div,phi,vort_hat,div_hat,phi_hat)

!        input scaling:

!     for schemes B, C:

!           vort_hat(n) = erad*vort(n)/sqrt(n*(n+1))

!           div_hat(n)  = sqrt(-1)*erad*div(n)/sqrt(n*(n+1))

!           phi_hat(n)  = phi(n)/gspeed

!     for scheme D:

!           vort_hat(n) = erad*vort(n)

!           div_hat(n)  = sqrt(-1)*erad*div(n)

!           phi_hat(n)  = phi(n)*sqrt(n*(n+1))/gspeed

    use kinds, only: i_kind,r_kind
    use constants, only: zero,one,rearth
    use mod_strong, only: scheme
    implicit none

    real(r_kind),intent(inout)::vort(2,m:mmax),div(2,m:mmax),phi(2,m:mmax)
    real(r_kind),intent(in)::vort_hat(2,m:mmax),div_hat(2,m:mmax),phi_hat(2,m:mmax)

    integer(i_kind) n,nstart

    nstart=max(m,1)
    if(scheme.ne.'D') then
      do n=nstart,mmax
        vort(1,n)=vort(1,n)+vort_hat(1,n)*rearth/sqrt(n*(n+one))
        vort(2,n)=vort(2,n)+vort_hat(2,n)*rearth/sqrt(n*(n+one))
        div(1,n)=div(1,n)+div_hat(2,n)*rearth/sqrt(n*(n+one))
        div(2,n)=div(2,n)-div_hat(1,n)*rearth/sqrt(n*(n+one))
        phi(1,n)=phi(1,n)+phi_hat(1,n)/gspeed
        phi(2,n)=phi(2,n)+phi_hat(2,n)/gspeed
      end do
    else
      do n=nstart,mmax
        vort(1,n)=vort(1,n)+rearth*vort_hat(1,n)
        vort(2,n)=vort(2,n)+rearth*vort_hat(2,n)
        div(1,n)=div(1,n)+div_hat(2,n)*rearth
        div(2,n)=div(2,n)-div_hat(1,n)*rearth
        phi(1,n)=phi(1,n)+sqrt(n*(n+one))*phi_hat(1,n)/gspeed
        phi(2,n)=phi(2,n)+sqrt(n*(n+one))*phi_hat(2,n)/gspeed
      end do
    end if

  end subroutine scale_vars_ad

  subroutine unscale_vars(vort_hat,div_hat,phi_hat,vort,div,phi)

!        output scaling:

!    for schemes B, C:

!           vort(n,m) = sqrt(n*(n+1))*vort_hat(n,m)/erad

!           div(n,m)  = -sqrt(-1)*sqrt(n*(n+1))*div_hat(n,m)/erad

!           phi(n,m)  = gspeed*phi_hat(n,m)

!    for scheme C:

!           vort(n,m) = vort_hat(n,m)/erad

!           div(n,m)  = -sqrt(-1)*div_hat(n,m)/erad

!           phi(n,m)  = gspeed*phi_hat(n,m)/sqrt(n*(n+1))

    use kinds, only: i_kind,r_kind
    use constants, only: zero,one,rearth
    use mod_strong, only: scheme
    implicit none

    real(r_kind),intent(in)::vort_hat(2,m:mmax),div_hat(2,m:mmax),phi_hat(2,m:mmax)
    real(r_kind),intent(out)::vort(2,m:mmax),div(2,m:mmax),phi(2,m:mmax)

    integer(i_kind) n,nstart

!   following is to account for 0,0 term being zero

    vort(1,m)=zero
    vort(2,m)=zero
    div(1,m)=zero
    div(2,m)=zero
    phi(1,m)=zero
    phi(2,m)=zero
    nstart=max(m,1)
    if(scheme.ne.'D') then
      do n=nstart,mmax
        vort(1,n)=vort_hat(1,n)*sqrt(n*(n+one))/rearth
        vort(2,n)=vort_hat(2,n)*sqrt(n*(n+one))/rearth
        div(1,n)=div_hat(2,n)*sqrt(n*(n+one))/rearth
        div(2,n)=-div_hat(1,n)*sqrt(n*(n+one))/rearth
        phi(1,n)=phi_hat(1,n)*gspeed
        phi(2,n)=phi_hat(2,n)*gspeed
      end do
    else
      do n=nstart,mmax
        vort(1,n)=vort_hat(1,n)/rearth
        vort(2,n)=vort_hat(2,n)/rearth
        div(1,n)=div_hat(2,n)/rearth
        div(2,n)=-div_hat(1,n)/rearth
        phi(1,n)=phi_hat(1,n)*gspeed/sqrt(n*(n+one))
        phi(2,n)=phi_hat(2,n)*gspeed/sqrt(n*(n+one))
      end do
    end if

  end subroutine unscale_vars

  subroutine unscale_vars_ad(vort_hat,div_hat,phi_hat,vort,div,phi)

!        output scaling:

!    for schemes B, C:

!           vort(n,m) = sqrt(n*(n+1))*vort_hat(n,m)/erad

!           div(n,m)  = -sqrt(-1)*sqrt(n*(n+1))*div_hat(n,m)/erad

!           phi(n,m)  = gspeed*phi_hat(n,m)

!    for scheme C:

!           vort(n,m) = vort_hat(n,m)/erad

!           div(n,m)  = -sqrt(-1)*div_hat(n,m)/erad

!           phi(n,m)  = gspeed*phi_hat(n,m)/sqrt(n*(n+1))

    use kinds, only: i_kind,r_kind
    use constants, only: zero,one,rearth
    use mod_strong, only: scheme
    implicit none

    real(r_kind),intent(inout)::vort_hat(2,m:mmax),div_hat(2,m:mmax),phi_hat(2,m:mmax)
    real(r_kind),intent(in)::vort(2,m:mmax),div(2,m:mmax),phi(2,m:mmax)

    integer(i_kind) n,nstart

    nstart=max(m,1)
    if(scheme.ne.'D') then
      do n=nstart,mmax
        vort_hat(1,n)=vort_hat(1,n)+vort(1,n)*sqrt(n*(n+one))/rearth
        vort_hat(2,n)=vort_hat(2,n)+vort(2,n)*sqrt(n*(n+one))/rearth
        div_hat(2,n)=div_hat(2,n)+div(1,n)*sqrt(n*(n+one))/rearth
        div_hat(1,n)=div_hat(1,n)-div(2,n)*sqrt(n*(n+one))/rearth
        phi_hat(1,n)=phi_hat(1,n)+phi(1,n)*gspeed
        phi_hat(2,n)=phi_hat(2,n)+phi(2,n)*gspeed
      end do
    else
      do n=nstart,mmax
        vort_hat(1,n)=vort_hat(1,n)+vort(1,n)/rearth
        vort_hat(2,n)=vort_hat(2,n)+vort(2,n)/rearth
        div_hat(2,n)=div_hat(2,n)+div(1,n)/rearth
        div_hat(1,n)=div_hat(1,n)-div(2,n)/rearth
        phi_hat(1,n)=phi_hat(1,n)+phi(1,n)*gspeed/sqrt(n*(n+one))
        phi_hat(2,n)=phi_hat(2,n)+phi(2,n)*gspeed/sqrt(n*(n+one))
      end do
    end if

  end subroutine unscale_vars_ad

  subroutine f_mult(x,y,f)

!    x = F*y

    use kinds, only: i_kind,r_kind
    use constants, only: zero
    implicit none

    real(r_kind),intent(in)::y(2,m:mmax),f(m:mmax)
    real(r_kind),intent(out)::x(2,m:mmax)

    integer(i_kind) n,nstart

    if(m.eq.mmax) then
      x=zero
      return
    end if

!   following is to account for 0,0 term being zero

    x(1,m)=zero
    x(2,m)=zero
    nstart=max(m,1)

    x(1,mmax)=zero
    x(2,mmax)=zero
    if(nstart.lt.mmax) then

      do n=nstart,mmax-1
        x(1,n)=f(n+1)*y(1,n+1)
        x(2,n)=f(n+1)*y(2,n+1)
      end do
      do n=nstart+1,mmax
        x(1,n)=x(1,n)+f(n)*y(1,n-1)
        x(2,n)=x(2,n)+f(n)*y(2,n-1)
      end do
    end if

  end subroutine f_mult

  subroutine c_mult(x,y,c)

!    x = C*y

    use kinds, only: i_kind,r_kind
    use constants, only: zero
    implicit none

    real(r_kind),intent(in)::y(2,m:mmax),c(m:mmax)
    real(r_kind),intent(out)::x(2,m:mmax)

    integer(i_kind) n,nstart


!   following is to account for 0,0 term being zero

    x(1,m)=zero
    x(2,m)=zero
    nstart=max(m,1)

    do n=nstart,mmax
      x(1,n)=c(n)*y(1,n)
      x(2,n)=c(n)*y(2,n)
    end do

  end subroutine c_mult

  subroutine i_mult(x,y)

!    x = sqrt(-1)*y

    use kinds, only: i_kind,r_kind
    use constants, only: zero
    implicit none

    real(r_kind),intent(in)::y(2,m:mmax)
    real(r_kind),intent(out)::x(2,m:mmax)

    integer(i_kind) n,nstart


!   following is to account for 0,0 term being zero

    x(1,m)=zero
    x(2,m)=zero
    nstart=max(m,1)

    do n=nstart,mmax
      x(1,n)=-y(2,n)
      x(2,n)=y(1,n)
    end do

  end subroutine i_mult

  subroutine solve_f2c2(x,y,f,c)

!    solve (F*F+C*C)*x = y

    use kinds, only: i_kind,r_kind
    use constants, only: zero
    implicit none

    real(r_kind),intent(in)::y(2,m:mmax),f(m:mmax),c(m:mmax)
    real(r_kind),intent(out)::x(2,m:mmax)

    integer(i_kind) n,nstart
    real(r_kind) a(m:mmax),b(m:mmax),z(2,m:mmax)


!   following is to account for 0,0 term being zero

    x(1,m)=zero
    x(2,m)=zero
    nstart=max(m,1)

!     copy forcing y to internal array

    do n=nstart,mmax
      z(1,n)=y(1,n)
      z(2,n)=y(2,n)
    end do

!     if nstart.eq.mmax, then trivial solution

    if(nstart.eq.mmax) then
      a(nstart)=c(nstart)*c(nstart)
      x(1,nstart)=z(1,nstart)/a(nstart)
      x(2,nstart)=z(2,nstart)/a(nstart)
    else

!       compute main diagonal of F*F + C*C

      a(nstart)=f(nstart+1)*f(nstart+1)+c(nstart)*c(nstart)
      if(nstart+1.lt.mmax) then
        do n=nstart+1,mmax-1
          a(n)=f(n)*f(n)+f(n+1)*f(n+1)+c(n)*c(n)
        end do
      end if
      a(mmax)=f(mmax)*f(mmax)+c(mmax)*c(mmax)

!       compute only non-zero off-diagonal of F*F + C*C

      if(nstart+2.le.mmax) then
        do n=nstart+2,mmax
          b(n)=f(n-1)*f(n)
        end do
      end if

!        forward elimination:

      if(nstart+2.le.mmax) then

        do n=nstart,mmax-2
          z(1,n+2)=z(1,n+2)-b(n+2)*z(1,n)/a(n)
          z(2,n+2)=z(2,n+2)-b(n+2)*z(2,n)/a(n)
          a(n+2)=a(n+2)-b(n+2)*b(n+2)/a(n)
        end do

      end if

!        backward substitution:

      x(1,mmax)=z(1,mmax)/a(mmax)
      x(2,mmax)=z(2,mmax)/a(mmax)
      x(1,mmax-1)=z(1,mmax-1)/a(mmax-1)
      x(2,mmax-1)=z(2,mmax-1)/a(mmax-1)
      if(nstart+2.le.mmax) then
        do n=mmax-2,nstart,-1
          x(1,n)=(z(1,n) - b(n+2)*x(1,n+2))/a(n)
          x(2,n)=(z(2,n) - b(n+2)*x(2,n+2))/a(n)
        end do
      end if

    end if

  end subroutine solve_f2c2
          
end module mod_inmi
