! 1D Langmuir turbulence simulation according to Guio and Forme 2006
! Last update: 9/5/2013
! For Kappa on: 01/05/2016

! Michael Hirsch Oct 2013 -- updated vbeam,tetabeam to use C++ vector format

program zakharov1d

use, intrinsic:: iso_fortran_env, only: wp=>real64, i64=>int64
use perf, only: sysclock2ms

implicit none

!integer(i64) :: tic, toc

real(wp), parameter :: pi = 4.0_wp * atan(1.0_wp),&
                       me=9.10938356e-31_wp, & ! kg
                       electroncharge=1.60217662e-19_wp, & ! coulombs
                       mi=16*1.66e-27_wp, & ! atomic oxygen
                       Kb=1.38064852e-23_wp, &    ! Boltzmann cte
                       eV=1.602176565e-19_wp, epsilon0=8.854187817e-12_wp

real(wp), parameter :: Te=3000.0_wp, Ti=1000.0_wp, Z=1.0_wp, &
                       nuic=1.0_wp, & ! ion collision freq
                       nuec=100.0_wp, & ! electron collision freq
                       n0=5.0e11_wp ! background density

real(wp), parameter :: vbeam_ev(1) = [500.0_wp]
integer, parameter :: Nvbeam=size(vbeam_ev)
real(wp) :: vbeam(Nvbeam), tetabeam(Nvbeam)


real(wp), parameter :: power_n_cte=7.7735e6_wp / sqrt(53.5_wp),&
                       power_E_cte=0.5033_wp*0.5033_wp / sqrt(3.0_wp)

!    Kappa parameters
! look at Broughton et al., Modeling of MF wave mode conversion
real(wp), parameter :: se_percent=0.001_wp, kappa=1.584_wp, T_se=18.2_wp*eV, &
                       theta_se=sqrt((kappa-1.5_wp)/kappa*2.0_wp*T_se/me), &
                       se_cte= 0.7397_wp / theta_se**3.0_wp

!    Simulation parameters

real(wp) :: endTime !100.0e-3_wp ! simulation ends (seconds)
real(wp), parameter :: Tstep=0.5e-7_wp ! simulation time steps
integer :: TT, TT_res               ! TT=floor(endTime/Tstep)+2
integer, parameter :: res=20
!TT_res=floor(endTime/Tstep/res)

real(wp), parameter :: L=70.0_wp           ! simulation box length (meter)j
integer :: N
real(wp) :: Xstep
integer, parameter :: QW=1     ! number of realizations

integer, allocatable :: SEED(:)
integer :: Nseed, clock


real(wp), parameter :: eta=(Te+3.0_wp*Ti) / Te, &
                       ve=sqrt(Kb*Te/me), &
                       Cs=sqrt(eta*me/mi)*ve, &
                       omegae=sqrt(n0*electroncharge**2.0_wp/me/epsilon0), &
                       lambdaD=ve/omegae

real(wp), allocatable :: beamev(:), nbeam(:)
integer :: Nnbeam

character(:), allocatable :: odir, ofn
character(256) :: argv
integer :: argc,i, ii,iij1, q,tt1,c1,c2,beami, beamj, realization,u,uEE,uNN
real(wp) :: tic1,toc1

!---- main loop variables

real(wp) :: Xsection_ion, Xsection_pl, E_thermal_k_squared, n_thermal_k_squared, &
  gamas,  gamal1, gamal2, gamal3, gamal

type params

  real(wp) :: pi, me,electroncharge,mi, Kb,eV,epsilon0, Z,Te, Ti, nuic, nuec, n0, nbeam, &
            vbeam_ev, vbeam, tetabeam, endTime, Tstep, TT, res, TT_res, L, N, Xstep, QW, &
            eta, ve, Cs, omegae, lambdaD
!  	have to include other parameters regarding the Kappa distribution

end type params

type(params) :: parameters

integer, allocatable :: p(:)

real(wp) :: CC(2), SSn(2), cte1, cte2, kn1(2), kn2(2), kn3(2), kn4(2), kv1(2), kv2(2), kv3(2), kv4(2)

real(wp), allocatable :: Source_factor_E(:), rdist(:), k(:),  Source_factor_n(:), omegaL(:), nui(:), nue(:), output1(:,:), &
EE(:,:,:), nn(:,:,:), vv(:,:,:), SSE(:,:), k1(:,:), k2(:,:), k3(:,:), k4(:,:)

integer :: LL,UU,pp

N = 2046
!! number of samples in L should be divisible by 6

Xstep = L / N

allocate(p(N))
allocate(rdist(N), k(N), Source_factor_n(N), Source_factor_E(N), omegaL(N), nui(N), nue(N), output1(N,12), &
   EE(3,N,2), nn(3,N,2), vv(3,N,2), SSE(N,2), k1(N,2), k2(N,2), k3(N,2), k4(N,2))


!---- argparse
argc = command_argument_count()
if (argc < 3) error stop 'must input:   outputDirectory endTime beamEnergy(s)'

call get_command_argument(1,argv)
odir = trim(argv)
print *,'writing output to', odir
call execute_command_line('mkdir -p '//odir)

call get_command_argument(2,argv)
read(argv,*) endTime
TT = floor(endTime / Tstep)
TT_res = floor(endTime/Tstep/res)

allocate(beamev(argc-2))
do i = 3,argc
   call get_command_argument(i,argv)
    read(argv,*) beamev(i-2)
enddo

Nnbeam = size(beamev)

nbeam = beamev*n0

print *, "Nnbeam=", Nnbeam, "Nvbeam=",Nvbeam, "TT=",TT,"time steps"

call cpu_time(tic1)

! initialization

vbeam=sqrt(eV*vbeam_ev*2/me)
 tetabeam=0.3*vbeam

print *,"vbeam=",vbeam,"tetabeam=",tetabeam

call random_seed(size=nseed)
allocate(seed(nseed))
seed(:) = 600  ! FIXME: arbitrary for simulation repeatability

nbm: do beami=1,Nnbeam
vbm: do beamj=1,Nvbeam

  parameters%pi = pi
  parameters%me = me
  parameters%electroncharge = electroncharge
  parameters%mi = mi
  parameters%Kb = Kb
  parameters%eV = eV
  parameters%epsilon0= epsilon0
  parameters%Z = Z
  parameters%Te = Te
  parameters%Ti = Ti
  parameters%nuic = nuic
  parameters%nuec= nuec
  parameters%n0 = n0
  parameters%nbeam = nbeam(beami)
  parameters%vbeam_ev = vbeam_ev(beamj)
  parameters%vbeam = vbeam(beamj)
  parameters%tetabeam = tetabeam(beamj)
  parameters%endTime = endTime
  parameters%Tstep = Tstep
  parameters%TT = TT
  parameters%res = res
  parameters%TT_res = TT_res
  parameters%L = L
  parameters%N = N
  parameters%Xstep = Xstep
  parameters%QW = QW
  parameters%eta = eta
  parameters%ve = ve
  parameters%Cs = Cs
  parameters%omegae = omegae
  parameters%lambdaD = lambdaD

  write(argv,'(A,I0.3,A,I0.3,A)')  odir//"/parameters_n" , beami, "_v" , beamj,'.bin'
  ofn = trim(argv)

  open(newunit=u, file=ofn, status='replace',action='write', access='stream')
  write(u) parameters, real(SEED,wp)
  close(u)
  print *, "Wrote parameters to ",ofn

  do ii=1,N
    p(ii)=ii-N/2

    if (ii==N/2) then
      k(ii) = 0
      Xsection_ion=0.0_wp
      Xsection_pl=0.0_wp
      n_thermal_k_squared=0.0_wp
      E_thermal_k_squared=0.0_wp
    else
      k(ii)=2*pi*p(ii)/N/Xstep
      call Xsection(Xsection_ion,Xsection_pl,k(ii))
      Xsection_ion=Xsection_ion/N**2
      Xsection_pl=Xsection_pl/N**2
      n_thermal_k_squared=Xsection_ion*n0
      E_thermal_k_squared=Xsection_pl *n0* (electroncharge/epsilon0/k(ii))**2.0_wp
    end if

    omegaL(ii)=sqrt(omegae**2.0_wp + 3.0_wp*(k(ii)*ve)**2.0_wp)
    gamas= -1.0_wp*sqrt(pi/8)*(sqrt(me/mi) + (Te/Ti)**2.0_wp / sqrt(Te/Ti) * &
            exp(-1.0_wp*(Te/2.0_wp/Ti)-1.5_wp))*abs(k(ii))*Cs
		!gamas= -1.0_wp*sqrt(pi/2)*(sqrt(me/mi) + 4*(Te/2/Ti)**2 / sqrt(Te/2/Ti) * &
!            exp(-1.0_wp*(Te*4/Ti)))*abs(k(ii))*Cs*10   ! based on Robinson 2002
		!gamas= -1.0_wp*sqrt(pi/8)*(1/(1+k(ii)*k(ii)*lambdaD*lambdaD)+3*Ti/Te)**2 / &
!              sqrt(1/(1+k(ii)*k(ii)*lambdaD*lambdaD)+3*Ti/Te)*(sqrt(me/mi)+(Te/Ti)**2 / &
!               sqrt(Te/Ti)*exp(-1.0_wp*(Te/2.0_wp/Ti)/(1+k(ii)*k(ii)*lambdaD*lambdaD)-1.5_wp)) * &
!               abs(k(ii))*Cs   ! Based on some Chinese paper!!
    nui(ii)=(nuic/2-gamas)

    if (ii==N/2) then
      gamal=0.0_wp           ! this one is Nan due to division by zero
      gamal1=0.0_wp
      nue(ii)=nuec/2.0_wp-gamal1
      Source_factor_n(ii)=0.0_wp
      Source_factor_E(ii)=0.0_wp
    else
      gamal1=-1.0_wp*sqrt(pi/8) * (omegae/k(ii)/ve)**2.0_wp * sign(1.0_wp,k(ii)) * omegaL(ii)**2.0_wp / &
              (k(ii)*ve) * exp(-1.0_wp*(omegaL(ii)/k(ii)/ve)**2.0_wp/2)  !Landau damping due to the thermal electrons

      gamal2=-1.0_wp*sqrt(pi/8)* (omegae / k(ii) / tetabeam(beamj))**2.0_wp * sign(1.0_wp,k(ii)) * nbeam(beami) / &
              n0*omegaL(ii)*(omegaL(ii)-k(ii)*vbeam(beamj)) / (k(ii)*tetabeam(beamj)) * &
              exp(-1.0_wp* (omegaL(ii)-k(ii)*vbeam(beamj) / k(ii) / tetabeam(beamj))**2.0_wp/2) !Landau damping due to the beam
      !gamal2=-1.0_wp*sqrt(pi/8)*(omegae/k(ii)/tetabeam(beamj))**2 * sign(1.0_wp,k(ii)) * &
!             nbeam(beami)/n0*omegaL(ii)*(omegaL(ii)-k(ii)*vbeam(beamj))/(k(ii)*tetabeam(beamj))* &
!             exp(-1.0_wp*((omegaL(ii)-k(ii)*vbeam(beamj))/k(ii)/tetabeam(beamj))**2/2)  ! Landau damping due to the beam
      gamal3=-1.0_wp*sqrt(pi)* (omegae*omegaL(ii))**2.0_wp / k(ii)**3.0_wp * sign(1.0_wp,k(ii)) *se_cte * &
              (1.0_wp + omegaL(ii)**2.0_wp/kappa/ (k(ii)*theta_se)**2.0_wp)**(-1.0_wp*(kappa+1))

      gamal=gamal1*(1-se_percent)+gamal2+se_percent*gamal3 ! here decide to include the beam and Kappa distribution
      nue(ii) = nuec/2-gamal1

      Source_factor_n(ii)=2*nui(ii)*sqrt(4*nui(ii)*k(ii)*k(ii)/(4*nui(ii)*nui(ii)+k(ii)*k(ii))* &
                          n_thermal_k_squared*power_n_cte)
      ! source factor is the factor by which we balance the thermal source intensity
      Source_factor_E(ii)=sqrt(2*nue(ii)*E_thermal_k_squared*power_E_cte)
      nue(ii)=nuec/2-gamal
    end if


    output1(ii,1) = p(ii)
    output1(ii,2) = k(ii)
    output1(ii,3) = Xsection_ion
    output1(ii,4) = Xsection_pl
    output1(ii,5) = E_thermal_k_squared
    output1(ii,6) = n_thermal_k_squared
    output1(ii,7) = omegaL(ii)
    output1(ii,8) = gamas
    output1(ii,9) = nui(ii)
    output1(ii,10) = nue(ii)
    output1(ii,11) = Source_factor_E(ii)
    output1(ii,12) = Source_factor_n(ii)
  end do ! ii

  !print *,output1(1,:)


  write(argv,'(A,I0.3,A,I0.3,A)') odir//"/output1_n",beami,"_v", beamj,'.bin'
  open(newunit=u,file=trim(argv),status='replace',action='write',access='stream')

  write(u) output1
  close(u)
  print *, "Wrote to ", trim(argv)


  rlz: do realization=1,QW
    cte2=omegae/2.0_wp/n0

    call system_clock(clock)
!    seed = clock + 37 * [ (i - 1, i = 1, nseed) ]
    call random_seed(put=seed)

    write(argv,'(A,I0.3,I0.3,A,I0.3,A,I0.3,A)') odir//"/EE",seed(1),realization,"_n",beami,"_v",beamj,".bin"
    open(newunit=uEE,file=trim(argv), status='replace',action='write',access='stream')
    print *,'writing to ',trim(argv)

    write(argv,'(A,I0.3,I0.3,A,I0.3,A,I0.3,A)') odir//"/nn",seed(1),realization, "_n" ,beami, "_v",beamj,'.bin'
    open(newunit=uNN,file=trim(argv), status='replace',action='write',access='stream')
    print *,'writing to ',trim(argv)

  !   main loops

    vv(:,:,:)=0.0_wp

    do iij1=1,3
      call random_number(rdist)
      EE (iij1,:,1)=sqrt(output1(:,5)/2.0_wp)*rdist
      call random_number(rdist)
      EE (iij1,:,2)=sqrt(output1(:,5)/2.0_wp)*rdist
      call random_number(rdist)
      nn (iij1,:,1)=sqrt(output1(:,6)/2.0_wp)*rdist
      call random_number(rdist)
      nn (iij1,:,2)=sqrt(output1(:,6)/2.0_wp)*rdist
    end do ! iij1 4

  !  print *,EE(3,3,2)
  !  stop

    nn(:,N-N/2+1:N,1) = nn(:,:N/2,1)
    nn(:,N-N/2+1:N,2) = -nn(:,:N/2,2) ! yes minus
    nn(:,N/2,:)=0.0_wp

    do tt1=1,TT

  !		int c0=(tt1-1) % 3
      c1= modulo(tt1, 3)+1
      c2= modulo(tt1+1, 3)+1
  !		long double omega_off=omegae+2*pi*300000

  		! update display every 50th iteration
      if (modulo(tt1,50) == 0) print '(A,I0.3,F7.2,A,I0.3,A,I0.3)',"Realization: ",&
          realization,tt1*100.0/TT,"% complete.  n",beami," v",beamj

      call calc_k1(N,nn,k1,SSE)


      do pp=1,N
        LL= max(p(pp)-N/3,-N/3)
        UU= min(N/3,p(pp)+N/3)
        CC(:)=0.0_wp

        do q=LL,UU
          CC(1)=CC(1)+(EE(c1,q+N/2,1)+k1(q+N/2,1)/2)*nn(c1,p(pp)-q+N/2,1)-(EE(c1,q+N/2,2)+k1(q+N/2,2)/2)*nn(c1,p(pp)-q+N/2,2)
          CC(2)=CC(2)+(EE(c1,q+N/2,1)+k1(q+N/2,1)/2)*nn(c1,p(pp)-q+N/2,2)+(EE(c1,q+N/2,2)+k1(q+N/2,2)/2)*nn(c1,p(pp)-q+N/2,1)
        end do

        cte1=1.5_wp*omegae*(lambdaD*k(pp))**2.0_wp
  			!cte1=1.5_wp*Kb*Te/me/omega_off*k(pp)*k(pp)-(omega_off**2-omegae**2)/2.0_wp/omega_off
        k2(pp,1)=Tstep*(cte1*(EE(c1,pp,2)+k1(pp,2)/2.0_wp-SSE(pp,1)/2.0_wp*Tstep) - &
                  nuE(pp) * (EE(c1,pp,1)+k1(pp,1)/2.0_wp+SSE(pp,2)/2.0_wp*Tstep)+cte2*CC(2))
        k2(pp,2)=Tstep*(-1.0_wp*cte1*(EE(c1,pp,1)+k1(pp,1)/2.0_wp+SSE(pp,2)/2.0_wp*Tstep) - &
                  nuE(pp)*(EE(c1,pp,2)+k1(pp,2)/2.0_wp-SSE(pp,1)/2.0_wp*Tstep)-cte2*CC(1))

      end do ! pp N


      do pp=1,N
        LL= max(p(pp)-N/3,-N/3)
        UU= min(N/3,p(pp)+N/3)
        CC(:)=0.0_wp

        do q=LL,UU
          CC(1)=CC(1)+(EE(c1,q+N/2,1)+k2(q+N/2,1)/2)*nn(c1,p(pp)-q+N/2,1)-(EE(c1,q+N/2,2)+k2(q+N/2,2)/2)*nn(c1,p(pp)-q+N/2,2)
          CC(2)=CC(2)+(EE(c1,q+N/2,1)+k2(q+N/2,1)/2)*nn(c1,p(pp)-q+N/2,2)+(EE(c1,q+N/2,2)+k2(q+N/2,2)/2)*nn(c1,p(pp)-q+N/2,1)
        end do

        cte1=1.5_wp*omegae*(lambdaD*k(pp))**2.0_wp
  			!cte1=1.5_wp*Kb*Te/me/omega_off*k(pp)*k(pp)-(omega_off**2-omegae**2)/2.0_wp/omega_off
        k3(pp,1)=Tstep*(cte1*(EE(c1,pp,2)+k2(pp,2)/2.0_wp-SSE(pp,1)/2.0_wp*Tstep) - &
                nuE(pp)*(EE(c1,pp,1)+k2(pp,1)/2.0_wp+SSE(pp,2)/2.0_wp*Tstep)+cte2*CC(2))
        k3(pp,2)=Tstep*(-1.0_wp*cte1*(EE(c1,pp,1)+k2(pp,1)/2.0_wp+SSE(pp,2)/2.0_wp*Tstep) - &
                nuE(pp)*(EE(c1,pp,2)+k2(pp,2)/2.0_wp-SSE(pp,1)/2.0_wp*Tstep)-cte2*CC(1))

      end do ! pp N


      do pp=1,N
        LL= max(p(pp)-N/3,-N/3)
        UU= min(N/3,p(pp)+N/3)
        CC(:)=0.0_wp

        do q=LL,UU
          ! no vect
          CC(1)=CC(1)+(EE(c1,q+N/2,1)+k3(q+N/2,1))*nn(c1,p(pp)-q+N/2,1)-(EE(c1,q+N/2,2)+k3(q+N/2,2))*nn(c1,p(pp)-q+N/2,2)
          CC(2)=CC(2)+(EE(c1,q+N/2,1)+k3(q+N/2,1))*nn(c1,p(pp)-q+N/2,2)+(EE(c1,q+N/2,2)+k3(q+N/2,2))*nn(c1,p(pp)-q+N/2,1)
        end do


        cte1=1.5_wp*omegae*(lambdaD*k(pp))**2.0_wp
  			!cte1=1.5_wp*Kb*Te/me/omega_off*k(pp)*k(pp)-(omega_off**2-omegae**2)/2.0_wp/omega_off
        k4(pp,1)=Tstep*(cte1*(EE(c1,pp,2)+k3(pp,2)-SSE(pp,1)*Tstep)-nuE(pp)*(EE(c1,pp,1)+k3(pp,1)+SSE(pp,2)*Tstep)+cte2*CC(2))
        k4(pp,2)=Tstep*(-1.0_wp*cte1*(EE(c1,pp,1)+k3(pp,1)+SSE(pp,2)*Tstep) - &
            nuE(pp)*(EE(c1,pp,2)+k3(pp,2)-SSE(pp,1)*Tstep)-cte2*CC(1))

        EE(c2,pp,1)=EE(c1,pp,1)+(k1(pp,1)+2.0_wp*k2(pp,1)+2.0_wp*k3(pp,1)+k4(pp,1))/6.0+SSE(pp,2) * Tstep ! no vect
        EE(c2,pp,2)=EE(c1,pp,2)+(k1(pp,2)+2.0_wp*k2(pp,2)+2.0_wp*k3(pp,2)+k4(pp,2))/6.0-SSE(pp,1) * Tstep ! no vect
        EE(c2,N/2,:)=0.0_wp
      end do ! pp N


      do pp=1,N/2
        call random_number(rdist(:2))
        SSn(:)= rdist(:2)*Source_factor_n(pp)/sqrt(Tstep)

        LL= max(p(pp)-N/3,-N/3)
        UU= min(N/3,p(pp)+N/3)
        CC(:)=0.0_wp

        do q=LL,UU
          ! no vect
          CC(1)=CC(1)+EE(c1,q+N/2,1)*EE(c1,q-p(pp)+N/2,1)+EE(c1,q+N/2,2)*EE(c1,q-p(pp)+N/2,2)
          CC(2)=CC(2)+EE(c1,q+N/2,2)*EE(c1,q-p(pp)+N/2,1)-EE(c1,q+N/2,1)*EE(c1,q-p(pp)+N/2,2)
        end do

        kn1(:)=Tstep*(vv(c1,pp,:))
        kv1(:)=Tstep*(-2.0_wp*nui(pp)*vv(c1,pp,:) - (Cs*k(pp))**2.0_wp *nn(c1,pp,:)-k(pp)**2.0_wp*epsilon0/4/mi*CC(:))

        CC(:)=0.0_wp

        do q=LL,UU
          ! no vect
          CC(1)=CC(1)+(EE(c1,q+N/2,1)+k1(q+N/2,1)/2)*(EE(c1,q-p(pp)+N/2,1)+k1(q-p(pp)+N/2,1)/2)+ &
                (EE(c1,q+N/2,2)+k1(q+N/2,2)/2)*(EE(c1,q-p(pp)+N/2,2)+k1(q-p(pp)+N/2,2)/2)
          CC(2)=CC(2)+(EE(c1,q+N/2,2)+k1(q+N/2,2)/2)*(EE(c1,q-p(pp)+N/2,1)+k1(q-p(pp)+N/2,1)/2)- &
                (EE(c1,q+N/2,1)+k1(q+N/2,1)/2)*(EE(c1,q-p(pp)+N/2,2)+k1(q-p(pp)+N/2,2)/2)
        end do

        kn2(:)=Tstep*(vv(c1,pp,:)+kv1(:)/2+SSn(:)/2*Tstep)

        kv2(:)=Tstep*(-2.0_wp*nui(pp)*(vv(c1,pp,:)+kv1(:)/2+SSn(:)/2*Tstep)- &
                (Cs*k(pp))**2.0_wp *(nn(c1,pp,:)+kn1(:)/2)-k(pp)**2.0_wp*epsilon0/4/mi*CC(:))

        CC(:)=0.0_wp

        do q=LL,UU
          CC(1)=CC(1)+(EE(c1,q+N/2,1)+k2(q+N/2,1)/2)*(EE(c1,q-p(pp)+N/2,1)+k2(q-p(pp)+N/2,1)/2) + &
                (EE(c1,q+N/2,2)+k2(q+N/2,2)/2)*(EE(c1,q-p(pp)+N/2,2)+k2(q-p(pp)+N/2,2)/2)
          CC(2)=CC(2)+(EE(c1,q+N/2,2)+k2(q+N/2,2)/2)*(EE(c1,q-p(pp)+N/2,1)+k2(q-p(pp)+N/2,1)/2) - &
                (EE(c1,q+N/2,1)+k2(q+N/2,1)/2)*(EE(c1,q-p(pp)+N/2,2)+k2(q-p(pp)+N/2,2)/2)
        end do

        kn3(:)=Tstep*(vv(c1,pp,:)+kv2(:)/2+SSn(:)/2*Tstep)

        kv3(:)=Tstep*(-2.0_wp*nui(pp)*(vv(c1,pp,:)+kv2(:)/2+SSn(:)/2*Tstep) - &
               (Cs*k(pp))**2.0_wp *(nn(c1,pp,:)+kn2(:)/2)-k(pp)**2.0_wp*epsilon0/4/mi*CC(:))



        CC(:)=0.0_wp
        do q=LL,UU
          CC(1)=CC(1)+(EE(c1,q+N/2,1)+k3(q+N/2,1)/2)*(EE(c1,q-p(pp)+N/2,1)+k3(q-p(pp)+N/2,1)/2) + &
                (EE(c1,q+N/2,2)+k3(q+N/2,2)/2)*(EE(c1,q-p(pp)+N/2,2)+k3(q-p(pp)+N/2,2)/2)
          CC(2)=CC(2)+(EE(c1,q+N/2,2)+k3(q+N/2,2)/2)*(EE(c1,q-p(pp)+N/2,1)+k3(q-p(pp)+N/2,1)/2) - &
                (EE(c1,q+N/2,1)+k3(q+N/2,1)/2)*(EE(c1,q-p(pp)+N/2,2)+k3(q-p(pp)+N/2,2)/2)
        end do

        kn4(:)=Tstep*(vv(c1,pp,:)+kv3(:)+SSn(:)*Tstep)
        kv4(:)=Tstep*(-2.0_wp*nui(pp)*(vv(c1,pp,:)+kv3(:)+SSn(:)*Tstep) - &
               (Cs*k(pp))**2.0_wp *(nn(c1,pp,:)+kn3(:))-k(pp)**2.0_wp*epsilon0/4/mi*CC(:))


        vv(c2,pp,:)=vv(c1,pp,:)+(kv1(:)+2*kv2(:)+2*kv3(:)+kv4(:))/6+SSn(:)*Tstep
        nn(c2,pp,:)=nn(c1,pp,:)+(kn1(:)+2*kn2(:)+2*kn3(:)+kn4(:))/6
        nn(c2,N/2,:)=0.0_wp

        if (pp>=1) then
          nn(c2,N-pp,1)=nn(c2,pp,1)
          nn(c2,N-pp,2)=-nn(c2,pp,2)
        end if

      end do ! pp N/2

  ! WRITE TO FILE
      if ( modulo(tt1,res) == 0) then
      !  print *, 'updating output EE nn files'
        write(uEE) EE(c2,:,:)
        write(unn) nn(c2,:,:)
      end if

    end do ! tt1

    close(uEE)
    close(unn)

  end do rlz !realizations
end do vbm !Nvbeam
end do nbm !Nnbeam


call cpu_time(toc1)
print *,"Elapsed Time: ", toc1-tic1


contains


subroutine calc_k1(N,nn, k1,SSE)

integer :: pp
integer, intent(in) :: N
real(wp), intent(in) :: nn(3,N,2)
real(wp),intent(out) :: k1(N,2), SSE(N,2)
real(wp) :: CC(2) = 0.0_wp

!integer(i64) :: tic, toc

do pp=1,N

  LL = max(p(pp)-N/3,-N/3)
  UU = min(N/3,p(pp)+N/3)
  CC(:)=0.0_wp

  do q=LL,UU
    CC(1) = CC(1)+EE(c1,q+N/2,1)*nn(c1,p(pp)-q+N/2,1)-EE(c1,q+N/2,2)*nn(c1,p(pp)-q+N/2,2)
    CC(2) = CC(2)+EE(c1,q+N/2,1)*nn(c1,p(pp)-q+N/2,2)+EE(c1,q+N/2,2)*nn(c1,p(pp)-q+N/2,1)
  end do

  call random_number(rdist(:2))
  SSE(pp,:) = rdist(:2)*Source_factor_E(pp)/sqrt(Tstep)

  cte1=1.5_wp*omegae*(lambdaD*k(pp))**2.0_wp
	!cte1=1.5_wp*Kb*Te/me/omega_off*k(pp)*k(pp)-(omega_off**2-omegae**2)/2.0_wp/omega_off
  k1(pp,1)=Tstep*(cte1*EE(c1,pp,2)-nuE(pp)*EE(c1,pp,1)+cte2*CC(2))
  k1(pp,2)=Tstep*(-1.0_wp*cte1*EE(c1,pp,1)-nuE(pp)*EE(c1,pp,2)-cte2*CC(1))
end do ! pp N


end subroutine calc_k1


elemental subroutine Xsection(Xsec_ion, Xsec_pl, k)
  implicit none

  real(wp), intent(out) :: Xsec_ion, Xsec_pl
  real(wp), intent(in) :: k

  real(wp) :: alpha,XX

  alpha=1.0_wp / (k*lambdaD)
  Xsec_ion= 2.0_wp * pi/(1.0_wp + alpha**2.0_wp) * (Z * alpha**4.0_wp/(1.0_wp+alpha**2.0_wp + alpha**2.0_wp * Z*Te/Ti))
  XX=2.0_wp*pi*(1.0_wp + alpha**2.0_wp*Z*Te/Ti)/(1.0_wp+alpha**2.0_wp+alpha**2.0_wp*Z*Te/Ti)

  Xsec_pl=XX-Te/Ti*Xsec_ion

end subroutine Xsection


end program
