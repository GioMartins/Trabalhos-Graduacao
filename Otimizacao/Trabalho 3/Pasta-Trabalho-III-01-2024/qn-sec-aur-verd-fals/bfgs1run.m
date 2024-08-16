% ================================================================
% ================================================================  
  function [x, f, rd] = bfgs1run(pars, ops)
% Initialize:
  rd.curstate = 0;
  tic;
  x     = ops.x0;
  [f,g] = feval(pars.fgname, x, pars);
  gnorm = norm(g);


% A     = randn(pars.nvar);
% [Q,R] = qr(A);
% S     = abs(diag(rand(pars.nvar,1)));
% H     = Q*S*Q';
  H     = eye(pars.nvar);
% p     = -g/gnorm; % first search direction.
% X     = randn(pars.nvar);
% H     = X'*X;
  p     = -H*g; %/ gnorm;

  rd.fsall    = [];
  fsalleval   = f;
  rd.nfeval   = 1;
  nfevallsrch = 1;
  initialchecks_solver(f,g,gnorm,ops);
  
% printing:
  printfunc(1,ops,pars,rd);
  
  for k = 1:ops.maxit
      t1 = toc;
      
      % ---------- gather data --------------
      if ops.gathdata
          rd.xs(:,k)        = x;
          rd.gs(:,k)        = g;
          rd.ps(:,k)        = p;
      end
      rd.fsall(end+1:end+nfevallsrch) = fsalleval;
      rd.k                  = k;
      % ---------- end gather data --------------
      
      gtp   = g'*p; % negative if p is descent dir
      [rd.curstate,rd.prtstr] = checkfordescentdir_solver(gtp);
      if rd.curstate ~= 0
          rd.ttime = sum(rd.times);
          printfunc(3,ops,pars,rd);
          return
      end
      
    % (Weak Wolfe) line search:
      [alpha, xkp1, f, gkp1, rd.lsfail,beta,gbeta,nfevallsrch,fsalleval] = ...
       linesch_ww(x, f, g, p, pars, ops.wolfe1, ops.wolfe2,...
       ops.fvalquit, ops.prtlvl);
      
      rd.nfevalcumu(k) = rd.nfeval;
      rd.fs(k)     = f;
      gnorm        = norm(gkp1);
      rd.gnorms(k) = gnorm;
      rd.nfeval    = rd.nfeval+nfevallsrch;
      rd.alphas(k) = alpha;
      curss        = xkp1 - x;
      rd.stpszs(k) = norm(curss);
      
      % ------------ printing --------------------
      printfunc(2,ops,pars,rd);
      % ------------- end printing ---------------
      
      % ---------- Check current status of algorithm --------
      [rd.curstate,rd.prtstr] = checkstatus_solver(rd,ops,pars);
      if rd.curstate ~= 0
          rd.fs(:,k+1)       = f;
          rd.fsall(end+1:end+nfevallsrch) = fsalleval;
          rd.gnorms(k+1)     = gnorm;
          rd.nfevalcumu(k+1) = rd.nfeval;
          t2                 = toc;
          rd.times(k)        = t2-t1;
          rd.ttime           = sum(rd.times);
          printfunc(4,ops,pars,rd);
          printfunc(3,ops,pars,rd);
          if ops.gathdata
              rd.xs(:,k+1)   = xkp1;
              rd.gs(:,k+1)   = gkp1;
          end
          return
      end
      % ------------------------------------------------------
      % ----- BFGS UPDATE: ----------------------
      [p,H] = update_bfgs(p,alpha,gkp1,g,k,H);
      % ------- end BFGS UPDATE -----------------------
      
      x = xkp1;
      g = gkp1;
      t2 = toc;
      rd.times(k) = t2-t1;
      printfunc(4,ops,pars,rd);
      
  end % for loop
% ================================================================
% ================================================================
  function [p,H] = update_bfgs(pprev,alpha,gkp1,g,k,H)
  s       = alpha*pprev;
  y       = gkp1 - g;
  sty     = s'*y;
  if k == 1   % scale only after first iteration
      H = (sty/(y'*y))*H;
  end
  rho     = 1/sty;
  rhoHyst = rho*(H*y)*s';
  H       = H - rhoHyst' - rhoHyst + rho*s*(y'*rhoHyst) + rho*s*s';
  p       = -H*gkp1;  % next search dir
% ================================================================
% ================================================================  
  function [alpha, xalpha, falpha, gradalpha, fail, beta,...
            gradbeta, nfeval,fsalleval] = ...
            linesch_ww(x0, f0, grad0, d, pars, c1, c2, fvalquit, prtlevel)
% LINESCH_WW Line search enforcing weak Wolfe conditions, suitable
%            for minimizing both smooth and nonsmooth functions
% call:  [alpha, xalpha, falpha, gradalpha, fail, beta, gradbeta, nfeval] = ...
%         linesch_ww(x0, f0, grad0, d, pars, c1, c2, fvalquit, prtlevel);
%  Input
%   x0:      intial point
%   f0:      function value at x0
%   grad0:   gradient at x0
%   d:       search direction  
%   pars:    a structure that specifies the function name as well
%            anything else that the user needs to access in programming the
%            function and gradient values
%        pars.fgname:  name of function that returns function and gradient
%            it expects as input only x and pars, a parameter structure 
%            it is invoked by: [f,g] = feval(fgname, x, pars)
%   c1: Wolfe parameter for the sufficient decrease condition 
%          f(x0 + t d) <= f0 + c1*t*grad0'*d     (default 1e-4)
%   c2: Wolfe parameter for the WEAK condition on directional derivative
%          (grad f)(x0 + t d)'*d >= c2*grad0'*d  (default 0.9)
%        these should normally satisfy 0 < c1 < c2 < 1, but may
%        want c1 = c2 = 0 when function known to be nonsmooth
%        note: setting c2 very small may interfere with superlinear
%           convergence when function is smooth
%   fvalquit: quit immediately if f drops below this value, regardless
%        of the Wolfe conditions (default -inf)
%   prtlevel: 0 for no printing, 1 minimal (default), 2 verbose 
%
%  Output:
%   alpha:   steplength satisfying weak Wolfe conditions if one was found,
%             otherwise left end point of interval bracketing such a point
%             (possibly 0)
%   xalpha:  x0 + alpha*d
%   falpha:  f(x0 + alpha d)
%   gradalpha:(grad f)(x0 + alpha d)  
%   fail:    0 if both Wolfe conditions satisfied, or falpha < fvalquit
%            1 if one or both Wolfe conditions not satisfied but an
%               interval was found bracketing a point where both satisfied
%           -1 if no such interval was found, function may be unbounded below
%   beta:    same as alpha if it satisfies weak Wolfe conditions,
%             otherwise right end point of interval bracketing such a point
%             (inf if no such finite interval found)
%   gradbeta: (grad f)(x0 + beta d) (this is important for bundle methods)
%             (vector of nans if beta is inf)
%             
%   nfeval:  number of function evaluations

% The weak Wolfe line search is far less complicated that the standard 
% strong Wolfe line search that is discussed in many texts. It appears
% to have no disadvantages compared to strong Wolfe when used with
% Newton or BFGS methods on smooth functions, and it is essential for 
% the application of BFGS or bundle to nonsmooth functions as done in HANSO.
% However, it is NOT recommended for use with conjugate gradient methods,
% which require a strong Wolfe line search for convergence guarantees.
% Weak Wolfe requires two conditions to be satisfied: sufficient decrease
% in the objective, and sufficient increase in the directional derivative
% (not reduction in its absolute value, as required by strong Wolfe).
%
% There are some subtleties for nonsmooth functions.  In the typical case
% that the directional derivative changes sign somewhere along d, it is
% no problem to satisfy the 2nd condition, but descent may not be possible
% if the change of sign takes place even when the step is tiny. In this
% case it is important to return the gradient corresponding to the positive 
% directional derivative even though descent was not obtained. On the other 
% hand, for some nonsmooth functions the function decrease is steady
% along the line until at some point it jumps to infinity, because an
% implicit constraint is violated.  In this case, the first condition is
% satisfied but the second is not. All cases are covered by returning
% the end points of an interval [alpha, beta] and returning the function 
% value at alpha, but the gradients at both alpha and beta. 
% The assertion that [alpha,beta] brackets a point satisfying the
% weak Wolfe conditions depends on an assumption that the function 
% f(x + td) is a continuous and piecewise continuously differentiable 
% function of t, and that in the unlikely event that f is evaluated at
% a point of discontinuity of the derivative, g'*d, where g is the 
% computed gradient, is either the left or right derivative at the point
% of discontinuity, or something in between these two values.
% For functions that are known to be nonsmooth, setting the second Wolfe
% parameter to zero makes sense, especially for a bundle method.  However,
% for smooth functions this may prevent superlinear convergence.
% Line search quits immediately if f drops below fvalquit.
% Written by Michael Overton (overton@cs.nyu.edu)
  if nargin < 6  % check if the optional Wolfe parameters were passed
    c1 = 1e-4;
  end
  if nargin < 7
      c2 = 0.9;
  end
  if nargin < 8
      fvalquit = -inf;
  end
  if nargin < 9
      prtlevel = 1;
  end
  % if c1 < 0 | c1 > c2 | c2 >= 1 % allows c1 = c2 = 0
  %    if prtlevel > 0
  %        fprintf('linesch_ww: Wolfe parameters do not satisfy 0 <= c1 <= c2 <= 1')
  %    end
  % end
  fgname = pars.fgname;
  alpha = 0;  % lower bound on steplength conditions
  xalpha = x0;
  falpha = f0;
  gradalpha = grad0; % need to pass grad0, not grad0'*d, in case line search fails
  beta = inf;  % upper bound on steplength satisfying weak Wolfe conditions
  gradbeta = nan*ones(size(x0));
  g0 = grad0'*d;
  % if g0 >= 0
  %     error('linesch_ww: g0 is nonnegative, indicating d not a descent direction')
  % end
  dnorm = norm(d);
  if dnorm == 0
      error('linesch_ww: d is zero')
  end
  t = 1;  % important to try steplength one first
  nfeval = 0;
  nbisect = 0;
  nexpand = 0;
  % the following limits are rather arbitrary
  % nbisectmax = 30; % 50 is TOO BIG, because of rounding errors
  nbisectmax = max(30, round(log2(1e5*dnorm))); % allows more if ||d|| big
  nexpandmax = max(10, round(log2(1e5/dnorm))); % allows more if ||d|| small
  done = 0;
  while ~done
      x = x0 + t*d;
      nfeval = nfeval + 1;
      [f,grad] = feval(fgname, x, pars);
      fsalleval(nfeval) = f;
      if f < fvalquit % nothing more to do, quit
          fail = 0;
          alpha = t; % normally beta is inf
          xalpha = x;
          falpha = f;
          gradalpha = grad;
          return
      end
      gtd = grad'*d;
      % the first condition must be checked first
      if f > f0 + c1*t*g0 | isnan(f) % first condition violated, gone too far
          beta = t;
          gradbeta = grad; % discard f
      elseif gtd < c2*g0 | isnan(gtd) % second condition violated, not gone far enough
          alpha = t;
          xalpha = x;
          falpha = f;
          gradalpha = grad;
      else   % quit, both conditions are satisfied
          fail = 0;
          alpha = t;
          xalpha = x;
          falpha = f;
          gradalpha = grad;
          beta = t;
          gradbeta = grad;
          return
      end
      % setup next function evaluation
      if beta < inf
          if nbisect < nbisectmax
              nbisect = nbisect + 1;
              t = (alpha + beta)/2; % bisection
          else
              done = 1;
          end
      else
          if nexpand < nexpandmax
              nexpand = nexpand + 1;
              t = 2*alpha;  % still in expansion mode
          else
              done = 1;
          end
      end
  end % loop
% Wolfe conditions not satisfied: there are two cases
  if beta == inf % minimizer never bracketed
     fail = -1;
  else % point satisfying Wolfe conditions was bracketed
     fail = 1;
  end
% ================================================================
% ================================================================