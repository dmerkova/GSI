module sst_retrieval

!$$$  module documentation block
!                .      .    .                                       .
! module:    sst_retrieval   sst retrieval algorithm and realted subroutines   
! prgmmr: li, xu             org: np23                date: 2004-12-21
!
! abstract: SST retrieval setup and application 
!
! program history log:
!   2004-12-21 xu li
!
! Subroutines Included:
!   sub setup_sst_retrieval  - define parameters for SST retrieval
!   sub avhrr_sst_retrieval  - perform SST retrieval with AVHRR radiance, save results
!   sub spline_cub           - cubic spline interpolation for SST dependent bias correction
!   sub finish_sst_retrieval - close bufr output file
!
! Functions Included:
!
! Variable Definitions:
!
! attributes:
!   language: f90
!   machine:  ibm RS/6000 SP
!
!$$$
  use kinds, only: r_kind,r_single,i_kind
  use radinfo, only: numt

! Define parameters
  integer(i_kind),parameter,private:: lnbufr = 12

! Declare variables and arrays - global within module, but private to external code
  real(r_kind), dimension(0:1), private :: e_ts,e_ta,e_qa
  real(r_kind), dimension(numt), private:: x_bias_sst


contains

  subroutine setup_sst_retrieval(obstype,csatid,mype)
!$$$  subprogram documentation block
!                .      .    .                                       .
! subprogram:    setup_sst_retrieval       compute rhs of oi for sst retrieval
!   prgmmr: xu li            org: np23                date: 2004-12-21
!
! abstract: set up sst retrieval
!
! program history log:
!   2004-12-21  xu li
!   2005-02/16  xu li - modify the way to define bufr table for SST 
!                       physical retrieval
!   2006-02-03  derber  - modify for new obs control and obs count
!   2006-04-06  middlecoff - change lundx from 20 to lendian_in so 
!                            can be read as little endian
!   2006-07-28  derber  - modify hanling of lextra
!
!   input argument list:
!     obstype - type of tb observation
!     csatid  - satellite id
!     mype    - mpi task id
!
!   output argument list:
!
! attributes:
!   language: f90
!   machine:  ibm RS/6000 SP
!
!$$$
    use kinds, only: r_kind,r_single,i_kind
    use constants, only: one,izero,h1000,ttp
    use gsi_io, only: lendian_in
    implicit none

! Define parameters
  
    character(10), intent(in) :: obstype,csatid
    integer(i_kind), intent(in) :: mype

    integer(i_kind) iret,iyear,imon,iday,i
    character(9) :: string
    character(10) :: filex
    character(len=80) :: bufrtabf
    character(30) bufr_sst       ! bufr output for sst2dvar input

!   Open output bufr file and table for SST retrieval
    write(string,99)mype
99  format('.',I4.4)
    bufr_sst= 'bfsst_'//trim(obstype)//'.'//trim(csatid)//string
    open(lnbufr,file=trim(bufr_sst),form='unformatted')       ! open bufr data file

    bufrtabf = 'bftab_sstphr'
    open(lendian_in,file=trim(bufrtabf))                           ! open bufr table
    call openbf (lnbufr,'NODX',lendian_in)

!   Assign x cooridinate for SST dependent AVHRR radiance bias correction
    do i = 1, numt
       x_bias_sst(i) =  ttp - one + real(i-1)
    enddo

!   Assign error parameters for background (Ts, Ta, Qa)
!
!   Day time
    e_ts(0) = 0.50_r_kind; e_ta(0) = 1.20_r_kind; e_qa(0) = 0.95_r_kind

!   Night time
!
    e_ts(1) = 0.45_r_kind; e_ta(1) = 0.90_r_kind; e_qa(1) = 0.65_r_kind
  end subroutine setup_sst_retrieval

  subroutine avhrr_sst_retrieval(obstype,csatid,nchanl,&
       tnoise,varinv,ts5,sstnv,sstcu,temp,wmix,ts,tbc,obslat,obslon,zasat,&
       dtime,dtp_avh,tlapchn,predterms,emissivity,pangs,tbcnob,tb_obs, & 
       rad_diagsave,sfcpct,id_qc,nadir,mype,ireal,ipchan,duse)
!subprogram:    avhrr_sst_retrieval  compute sst retrieval from AVHRR radiances
!   prgmmr: Xu Li, John Derber          org: w/nmc2     date: 04-12-29
!
! abstract:  perform sst retrieval based on input radiative transfer info
!            save bufr output and satellite diagnostics files
!
! program history log:
!   2004-12-29 li
!   2005-04-18 treadon - add passed logical lextra
!   2005-9-28  derber - modify land mask stuff 
!   200604-27  derber - modify to do single profile
!
!   input argument list:
!     obstype      - observation type
!     nsig         - number of model layers
!     csatid       - satellite id
!     nchanl       - number of channels for instruments
!     tnoise       - error of observed radiance
!     varinv       - inverse error squared
!     ts5          - sst used in Radiative transfer and first guess for SST retrieval
!     sstnv        - navy sst retrieval
!     sstcu        - ncep rtg sst analysis for the current day
!     temp         - d(brightness temperature)/d(temperature)
!     wmix         - d(brightness temperature)/d(mixing ratio)
!     ts           - d(brightness temperature)/d(skin temperature)
!     tbc          - bias corrected (observed - simulated brightness temperatures)
!     obslat       - latitude of observations
!     obslon       - longitude of observations
!     iadate       - analysis time window (00, 06, 12, 18)
!     dtime        - observed time distance from iadate
!     dtp_avh      - night/day mode
!     rad_diagsave - logical to switch on diagnostic output (.false.=no output)
!     nadir        - number of FOV
!     ireal        - rank of array diagbuf
!     ipchan       - The first number (7) of elements in array diagbufchan 
!
! attributes:
!   language: f90
!   machine:  ibm RS/6000 SP
!
!$$$
    use kinds, only: r_kind,r_single,i_kind
    use radinfo, only: npred
    use gridmod, only: nsig
    use obsmod, only: iadate,rmiss_single
    use constants, only: zero,half,one,two,three,tiny_r_kind,izero,rad2deg,ttp

    implicit none

!   Declare local parameters
    integer(i_kind),parameter:: nmsg=11
    character(len=8), parameter :: subset='NC012017'
    real(r_kind),parameter:: r180=180.0_r_kind
    real(r_kind),parameter:: r360=360.0_r_kind

!   Declare passed variables
    integer(i_kind), intent(in) :: nchanl,mype,ireal,ipchan
    integer(i_kind), intent(in):: nadir
    real(r_kind),dimension(nchanl), intent(in) :: tnoise
    real(r_kind),dimension(nchanl), intent(in) :: varinv,tbc,tb_obs,tbcnob,tlapchn
    real(r_kind),dimension(nchanl), intent(in) :: emissivity
    real(r_kind),intent(in) :: obslat,obslon,pangs,zasat,dtime,ts5,&
         sstnv,sstcu,dtp_avh
    real(r_kind),dimension(nchanl), intent(in) :: ts
    real(r_kind),dimension(nsig,nchanl), intent(in) :: wmix,temp
    real(r_kind),dimension(npred+1,nchanl), intent(in) ::predterms
    character(10), intent(in) :: obstype,csatid
    logical, intent(in) :: rad_diagsave
    logical, intent(in) :: duse

!   Declare local variables
    real(r_kind) :: ws,wa,wq,errinv
    integer(i_kind) :: icount,idate,md,ch3,ch4,ch5,iret,nn,i,j,l,n,lndsea
    integer(i_kind) :: iextra,jextra
    real(r_kind), dimension(nchanl) :: tb_ta,tb_qa
    real(r_kind), dimension(nchanl) :: w_avh
    real(r_kind) :: delt,delt1,delt2,delt3,c1x,c2x,c3x
    real(r_kind) :: a11,a12,a13,a23,a22,a33
    real(r_kind) :: bt3,bt4,bt5,varrad,rsat
    real(r_kind) :: nuse
    logical :: lextra

!   Declare local arrays
    real(r_kind) :: sstph,dsst,dqa,dta
    integer(i_kind),dimension(8) :: idat8,jdat8
    real(r_kind), dimension(5) :: rinc
    real(r_kind), dimension(4) :: sfcpct
    real(r_kind), dimension(nmsg) :: bufrf
    integer(i_kind),dimension(nchanl):: id_qc
    
    real(r_single),dimension(ireal) :: diagbuf
    real(r_single),dimension(ipchan+npred+1,nchanl) ::diagbufchan
    real(r_single),allocatable,dimension(:,:) :: diagbufex

    ch3=1;ch4=2;ch5=3
    lextra=.false.
    iextra=0
    jextra=0
    if(obstype == 'avhrr' .or. obstype == 'avhrr_navy')then
      lextra=.true.
      iextra=3
      jextra=nchanl
    end if
    allocate (diagbufex(iextra,jextra))
!**********************************
! Get tb_ta & tb_qa
!**********************************
    do i = 1, nchanl
       tb_ta(i) = temp(1,i)
       tb_qa(i) = wmix(1,i)
       do l = 2, nsig
          tb_ta(i) = tb_ta(i) + temp(l,i)
          tb_qa(i) = tb_qa(i) + wmix(l,i)
       enddo
    enddo

    if (duse) then

    if (duse) then
      nuse = 1.0
    else
      nuse = 0.0
    endif

     dsst = rmiss_single; dta = rmiss_single; dqa = rmiss_single

!    Get day/night mode
     if ( dtp_avh /= 152.0_r_kind ) then
        md = 0                 ! Day time
     else
        md = 1                 ! Night time
     endif

     ws = one/e_ts(md)**2
     wa = one/e_ta(md)**2
     wq = one/(e_qa(md)*(max((ts5-ttp)*0.03_r_kind,zero)+0.1_r_kind))**2
     
     a11 = ws                                      ! 1./tserr**2
     a22 = wa                                      ! 1./taerr**2
     a33 = wq                                      ! 1./qaerr**2

     a12 = zero; a13 = zero; a23 = zero
     c1x = zero; c2x = zero; c3x = zero
     delt1 = zero; delt = one; icount = izero

     do l=1,nchanl

!       Get coefficients for linear equations
        if (varinv(l) > tiny_r_kind) then
           
           icount = icount+1
           
           w_avh(l) = (one/tnoise(l))**2
           
           a11 = a11 + w_avh(l)*ts(l)**2
           a12 = a12 + w_avh(l)*ts(l)*tb_ta(l)
           a13 = a13 + w_avh(l)*ts(l)*tb_qa(l)
           a22 = a22 + w_avh(l)*tb_ta(l)**2
           a23 = a23 + w_avh(l)*tb_ta(l)*tb_qa(l)
           a33 = a33 + w_avh(l)*tb_qa(l)**2
           
           varrad=w_avh(l)*tbc(l)
           
           c1x = c1x + varrad*ts(l)
           c2x = c2x + varrad*tb_ta(l)
           c3x = c3x + varrad*tb_qa(l)
           
        end if           ! if(varinv(l) > tiny_r_kind) then
     end do               ! do l=1,nchanl

!    Solve linear equations with three unknowns (dsst, dta, dqa)
     if( (dtp_avh == 152._r_kind .and. icount > 2 ) .or. &
          (dtp_avh /= 152._r_kind .and. icount > 1 ) ) then
        
        delt  =  a11*(a22*a33-a23*a23) +  &
                 a12*(a13*a23-a12*a33) +  &
                 a13*(a12*a23-a13*a22)
        
        delt1 =  c1x*(a22*a33-a23*a23) + &
                 c2x*(a13*a23-a12*a33) + &
                 c3x*(a12*a23-a13*a22)
        
        delt2 =  c1x*(a13*a23-a12*a33) + &
                 c2x*(a11*a33-a13*a13) + &
                 c3x*(a12*a13-a11*a23)
        
        delt3 =  c1x*(a12*a23-a13*a22) + &
                 c2x*(a13*a12-a11*a23) + &
                 c3x*(a11*a22-a12*a12)
        
        dsst = delt1/delt
        dta  = delt2/delt
        dqa  = delt3/delt
        
        sstph = ts5 + dsst                         ! SST retrieval : SSTPH
        
     
   bt3 = tb_obs(ch3) - tbc(ch3)
   bt4 = tb_obs(ch4) - tbc(ch4)
   bt5 = tb_obs(ch5) - tbc(ch5)
                             
!    if ( varinv(ch3) == zero ) then
!      bt3 = rmiss_single
!    endif

!   write(*,'(15f8.2,4F6.1,F3.0)') obslon,obslat,sstph,sstnv,ts5, &
!                       tb_obs(ch3),bt3,tb_obs(ch4),bt4,tb_obs(ch5),bt5, &
!                       sstph-ts5,dta,dqa,pangs,varinv(ch3),varinv(ch4),varinv(ch5),zasat,nuse

!                       ts(ch3),ts(ch4),ts(ch5), &
!                       tb_ta(ch3),tb_ta(ch4),tb_ta(ch5), &
!                       tb_qa(ch3),tb_qa(ch4),tb_qa(ch5), &


!       Save bufr message for physical SST retrieval with Navy AVHRR radiance
        idat8(1) = iadate(1)              ! 4-digit year
        idat8(2) = iadate(2)              ! months of a year
        idat8(3) = iadate(3)              ! days of a month
        idat8(4) = izero                  ! time zone
        idat8(5) = iadate(4)              ! hours of a day
        idat8(6) = izero                  ! minutes of a hour
        idat8(7) = izero                  ! seconds
        idat8(8) = izero                  ! milliseconds
        
        rinc(1) = dtime/24._r_kind
        rinc(2) = zero
        rinc(3) = zero
        rinc(4) = zero
        rinc(5) = zero
        
        call w3movdat(rinc,idat8,jdat8)
 
!    TRANSFORM THE NAVY AVHRR(GAC/NAVY) RECORD TO BUFR FORMAT
! ------------------------------------------------------------------------------
! NC012015 | YEAR MNTH DAYS HOUR MINU SECO CLATH CLONH SAID SIID SLNM FOVN     |
! NC012015 | HMSL SAZA SOZA SSTTYP IREL IRMS OPTH SST1 SST2 SST3               |
! NC012015 | ATB1 ATB2 ATB3 ATB4 ATB5 DTB1 DTB2 DTB3 DTB4 DTB5                 |
! ------------------------------------------------------------------------------
        bufrf( 1) = jdat8( 1)                        ! 4-digit year
        bufrf( 2) = jdat8( 2)                        ! month of a year
        bufrf( 3) = jdat8( 3)                        ! day of a month
        bufrf( 4) = jdat8( 5)                        ! hour of a day
        bufrf( 5) = jdat8( 6)                        ! minute of a hour
        bufrf( 6) = jdat8( 7)                        ! second of a minute
        bufrf( 7) = obslat                           ! Latitude
        bufrf( 8) = obslon                           ! Longitude
        if(bufrf(8) > r180) bufrf(8) = bufrf(8) - r360
        if(csatid == 'n15') rsat=206.0_r_kind
        if(csatid == 'n16') rsat=207.0_r_kind
        if(csatid == 'n17') rsat=208.0_r_kind
        if(csatid == 'n18') rsat=209.0_r_kind
        bufrf(9) = rsat                              ! Satellite ID (Data source)
        bufrf(10) = dtp_avh                          ! Type of observation/retrieval (151, 152, 159)
        bufrf(11) = sstph                            ! Physical SST retrieval

!       WRITE THIS ARRAY INTO BUFR
!       --------------------------
        idate=iadate(4)+iadate(3)*100+iadate(2)*10000+iadate(1)*1000000
        CALL OPENMB(lnbufr,subset,idate)
        CALL UFBSEQ(lnbufr,bufrf,nmsg,1,iret,subset)
        CALL WRITSB(lnbufr)
                                                                                                                                                             
!       Save diagnostics at the satellite observation locations
        if (rad_diagsave) then

!          Write diagnostics to output file.  Only generate
!          file on first outer iteration.
           diagbuf(1)  = obslat                         ! observation latitude (degrees)
           diagbuf(2)  = obslon                         ! observation longitude (degrees)
           diagbuf(3)  = rmiss_single                   ! model (guess) elevation at observation location
           
           diagbuf(4)  = dtime                          ! observation time (hours relative to analysis time)
           
           diagbuf(5)  = nadir                          ! sensor scan position
           diagbuf(6)  = zasat*rad2deg                  ! satellite zenith angle (degrees)
           diagbuf(7)  = rmiss_single                   ! satellite azimuth angle (degrees)
           diagbuf(8)  = pangs                          ! solar zenith angle (degrees)
           diagbuf(9)  = rmiss_single                   ! solar azimuth angle (degrees)
           diagbuf(10) = rmiss_single                   ! sun glint angle (degrees) (sgagl)
           
           diagbuf(11) = sfcpct(1)                      ! fractional coverage by water
           diagbuf(12) = sfcpct(2)                      ! fractional coverage by land
           diagbuf(13) = sfcpct(3)                      ! fractional coverage by ice
           diagbuf(14) = sfcpct(4)                      ! fractional coverage by snow
           diagbuf(15) = ts5                            ! SST first guess used for SST retrieval
           diagbuf(16) = sstcu                          ! NCEP SST analysis at t
           diagbuf(17) = sstph                          ! Physical SST retrieval
           diagbuf(18) = sstnv                          ! Navy SST retrieval
           diagbuf(19) = dta                            ! d(ta) corresponding to sstph
           diagbuf(20) = dqa                            ! d(qa) corresponding to sstph
           diagbuf(21) = dtp_avh                        ! data type
           diagbuf(22) = rmiss_single                   ! vegetation fraction
           diagbuf(23) = rmiss_single                   ! snow depth
           diagbuf(24) = rmiss_single                   ! surface wind speed (m/s)
           

!          Note:  The following quantities are not computed for all sensors
           diagbuf(25)  = rmiss_single                  ! cloud fraction (%)
           diagbuf(26)  = rmiss_single                  ! cloud top pressure (hPa)

           
           do i=1,nchanl
              diagbufchan(1,i)=tb_obs(i)       ! observed brightness temperature (K)
              diagbufchan(2,i)=tbc(i)          ! final observed minus simulated difference (K)
              diagbufchan(3,i)=tbcnob(i)       ! initial observed minus simulated difference (K)
              errinv = sqrt(varinv(i))
              diagbufchan(4,i)=errinv          ! inverse observation error
              diagbufchan(5,i)=id_qc(i)        ! quality control mark or event
              diagbufchan(6,i)=emissivity(i)   ! surface emissivity
              diagbufchan(7,i)=tlapchn(i)      ! stability index
              
              if ( nn == 1 .and. varinv(nn) == zero ) then
                 diagbufchan(1,nn) = rmiss_single                   
                 diagbufchan(2,nn) = rmiss_single                  
                 diagbufchan(3,nn) = rmiss_single                 
                 diagbufchan(4,nn) = rmiss_single                
                 diagbufchan(5,nn) = rmiss_single               
                 diagbufchan(6,nn) = rmiss_single              
                 diagbufchan(7,nn) = rmiss_single              
              endif
              
              do j=1,npred+1
                 diagbufchan(7+j,i)=predterms(j,i) ! brightness temperature bias correction terms (K)
              end do
              
              if (lextra) then
                 do nn=1,nchanl
                    diagbufex(1,nn)=ts(nn)              ! d(Tb)/d(Ts)
                    diagbufex(2,nn)=tb_ta(nn)           ! d(Tb)/d(Ta)
                    diagbufex(3,nn)=tb_qa(nn)           ! d(Tb)/d(Qa)
                 end do
              endif
              
           end do
           if (.not.lextra) then
              write(4) diagbuf,diagbufchan
           else
              write(4) diagbuf,diagbufchan,diagbufex
           endif
           
        end if              ! if (rad_diagsave) then
     end if                 ! if( (dtp_avh == 152. .and. icount > 2 ) .or. &
   end if                   ! if(duse) then 

  end subroutine avhrr_sst_retrieval

  subroutine spline_cub(y,xs,ys)
!$$$  subprogram documentation block
!                .      .    .                                       .
! subprogram:    spline_cub           one dimensional cubic spline interpolation
!   prgmmr: Xu Li            org: np23                date: 2003-09-01
!
! abstract: one dimensional cubic spline interpolation
!
! program history log:
!   2003-09-01 xu li
!
!   input argument list:
!     y - cubic spline value at knots
!    xs - interpolator
!
!   output argument list:
!     ys - interpolatee
!
! attributes:
!   language: f90
!   machine:  ibm RS/6000 SP
!
!$$$
    use kinds, only: r_kind,i_kind
    use constants, only: zero,half,one,two,three,izero

    implicit none

!   Passed variables
    real(r_kind) :: xs,ys
    real(r_kind), dimension(numt),intent(in) :: y

!   Local variables
    integer(i_kind) i,j,n
    real(r_kind), dimension(numt) :: g,a,d,m,k

!   handle the case when xs beyond [-1,31]
    if ( xs < x_bias_sst(1) )    xs = x_bias_sst(1)
    if ( xs > x_bias_sst(numt) ) xs = x_bias_sst(numt)

    do i = 1, numt - 1
       g(i) = one/(x_bias_sst(i+1) - x_bias_sst(i))
    enddo

    a(1) = half
    do i = 2, numt - 1
       a(i) = g(i)/(two*(g(i-1)+g(i)) - a(i-1)*g(i-1))
    enddo
    
    d(1) = 1.5_r_kind*(y(2) - y(1))/(x_bias_sst(2) - x_bias_sst(1))
    do i = 2, numt - 1
       d(i) = (three*(g(i-1)*(y(i)-y(i-1))/(x_bias_sst(i)-x_bias_sst(i-1))+g(i)*(y(i+1)-y(i))/(x_bias_sst(i+1)-x_bias_sst(i))) &
            -g(i-1)*d(i-1))/(two*(g(i-1)+g(i))-g(i-1)*a(i-1))
    enddo
    
    m(numt) = (three*(y(numt)-y(numt-1))/(x_bias_sst(numt)-x_bias_sst(numt-1)) - g(numt-1)*d(numt-1)) &
         /(g(numt-1)*(two-a(numt-1)))
    do i = numt-1, 1, -1
       m(i) = d(i) - a(i)*m(i+1)
    enddo
    
    k(1) = zero
    k(numt) = zero
    do i = 2, numt - 1
       k(i) = 6.0_r_kind*g(i)*(y(i+1)-y(i))/(x_bias_sst(i+1)-x_bias_sst(i)) - two*g(i)*(two*m(i)+m(i+1))
    enddo
    
    do j = 1, numt-1
       if ( xs >= x_bias_sst(j) .and. xs < x_bias_sst(j+1) ) then
          i = j
       endif
    enddo
    
    ys = y(i)+m(i)*(xs-x_bias_sst(i))+half*k(i)*(xs-x_bias_sst(i))**2 &
         + ((k(i+1)-k(i))/((x_bias_sst(i+1)-x_bias_sst(i))*6.0_r_kind))*(xs-x_bias_sst(i))**3
    
  end subroutine spline_cub

  subroutine finish_sst_retrieval
!$$$  subprogram documentation block
!                .      .    .                                       .
! subprogram:    finish_sst_retrieval             close open bufr file
!   prgmmr: treadon          org: np23                date: 2005-01-07
!
! abstract:  Finish sst retrieval code by closing bufr file
!
! program history log:
!   2005-01-07 treadon
!
!   input argument list:
!
!   output argument list:
!
! attributes:
!   language: f90
!   machine:  ibm RS/6000 SP
!
!$$$
    call closbf(lnbufr)
    return
  end subroutine finish_sst_retrieval
    
end module sst_retrieval
