% ---- settings ----
Pt    = 10;     % target PD power, dBm
db    = 0.12;   % deadband, dB
bmin  = 5;      % bias limits, a.u.
bmax  = 28;
D     = 1;      % loop lag in passes: PD in pass n reflects the bias output D passes earlier (1 = nominal)
seff  = 1.5;    % dB of PD per dB of bias (fitted range 1.36 to 1.68)
smin  = 1;      % error shift range: loop gain = 2^-s on the log2 error
smax  = 5;
calm  = 12;     % quiet updates before the shift is released by one step
adapt = true;   % false: fixed shift = smin
fd    = false;  % false: Sampled Signal Domain is Time
show  = true;   % popup each pass; set false once it works
SEG   = 32;     % LUT segments (hardware: log2 and 2^x tables)
D = max(1, round(D));

% ---- output folder: everything is written to the C drive ----
dirs = {'C:\laser_ctrl', 'C:\Users\Public', tempdir};
od = '';
for k0 = 1:3, d0 = dirs{k0}; if isempty(od) && ~exist(d0, 'dir'), try, mkdir(d0); catch, end, end, ft = -1; if isempty(od), ft = fopen(fullfile(d0, 'write_test.tmp'), 'a'); end, if ft > 0, fclose(ft); try, delete(fullfile(d0, 'write_test.tmp')); catch, end, od = d0; end, end
if isempty(od), od = tempdir; end
sf = fullfile(od, 'laser_bias_ctrl5_state.mat');   % controller memory between passes
lf = fullfile(od, 'laser_bias_ctrl5_log.csv');     % one line per pass

xs = (0:SEG)/SEG; LG = log2(1 + xs); EX = 2.^xs;   % LUT contents

sig1 = InputPort1;
sig2 = InputPort2;
S1 = double(sig1.Sampled.Signal);
bin = max(real(S1(:)));          % generator bias in a.u.

S2 = [];
try, S2 = double(sig2.Sampled.Signal); catch, end
fb_ok = ~isempty(S2);

% state: [log2 bias, pass count, shift, previous error sign, quiet counter, last D log2 biases]
st = [];
try, tmp = load(sf, 'st'); st = tmp.st; catch, end
bad = isempty(st) || numel(st) ~= 5 + D;
lost = fb_ok && bad;
if ~fb_ok || bad, L0 = log2(max(bin, eps)); st = [L0, 0, smin, 0, 0, L0*ones(1, D)]; end
L = st(1); n = st(2) + 1; s = st(3); sp = st(4); q = st(5); Lh = st(6:end);
b = 2^L;

% PD power and its log2 (leading-one detector + LUT interpolation)
Pw = 0;
if fb_ok, if fd, Pw = sum(abs(S2(:)).^2); else, Pw = mean(abs(S2(:)).^2); end, end
valid = fb_ok && isfinite(Pw) && Pw > 0;
LP = -200; PdB = -200; err = 0;
if valid, e1 = floor(log2(Pw)); m1 = Pw/2^e1 - 1; i1 = min(floor(m1*SEG), SEG-1); f1 = m1*SEG - i1; LP = e1 + LG(i1+1) + (LG(i1+2) - LG(i1+1))*f1; end
if valid, PdB = 10*log10(1000*Pw); end
LPt = Pt*log2(10)/10 - log2(1000);   % target in log2 of the accumulator value (constant)
if valid, err = LPt - LP; end
errdB = err*3.0103;                  % log2 units to dB

% delay compensation: moves commanded but not yet visible in the PD reading
pend = L - Lh(1);
ep = 0;
if valid, ep = err - seff*pend; end  % predicted error once the pending moves show up
epdB = ep*3.0103;

ok = valid && abs(errdB) < 30;       % a bigger error means a scale/domain mistake: hold
upd = ok && abs(ep) > db/3.0103;

% self-tuning shift: a sign flip means the loop is too aggressive
sg = sign(ep);
flip = upd && adapt && sp ~= 0 && sg ~= sp;
if flip, s = min(s + 1, smax); q = 0; end
if upd && ~flip, q = q + 1; end
if upd && ~flip && adapt && q >= calm && s > smin, s = s - 1; q = 0; end
if ~upd && ok, q = q + 1; end
if upd, sp = sg; end

% log-domain update: add the shifted predicted error, clamp the step and the range
Llim = log2(1.25);
dL = 0;
if upd, dL = max(min(ep/2^s, Llim), -Llim); end
Ln = L;
if upd, Ln = min(max(L + dL, log2(bmin)), log2(bmax)); end
sat = upd && ((Ln >= log2(bmax) && ep > 0) || (Ln <= log2(bmin) && ep < 0));

% antilog by LUT interpolation
e2 = floor(Ln); m2 = Ln - e2; i2 = min(floor(m2*SEG), SEG-1); f2 = m2*SEG - i2;
bn = 2^e2 * (EX(i2+1) + (EX(i2+2) - EX(i2+1))*f2);

st = [Ln, n, s, sp, q, [Lh(2:end), Ln]];
try, save(sf, 'st'); catch, end

% output: the input signal scaled, so its shape and domain are kept
OutputPort1 = sig1;
if bin > 0, OutputPort1.Sampled.Signal = S1 * (bn/bin); end

% log every pass (pass 1 starts a new file)
if ~fb_ok, fid = fopen(lf, 'w'); else, fid = fopen(lf, 'a'); end
if fid > 0 && ~fb_ok, fprintf(fid, 'pass,fb_ok,PD_dBm,err_dB,pred_err_dB,bias_applied,bias_next,shift,flip,sat,Pw\n'); end
if fid > 0, fprintf(fid, '%d,%d,%.4f,%.4f,%.4f,%.4f,%.4f,%d,%d,%d,%.6g\n', n, fb_ok, PdB, errdB, epdB, b, bn, s, flip, sat, Pw); fclose(fid); end

stat = 'hold';
if upd, stat = 'step'; end
if sat, stat = 'sat'; end
if fb_ok && ~valid, stat = 'nosig'; end
if valid && ~ok, stat = 'range'; end
extra = '';
if n == 1, extra = [' | log: ', lf, ' | state: ', sf]; end
if show, msgbox(['pass ', num2str(n), ' | ', stat, ' | PD = ', num2str(PdB, 5), ' dBm | err = ', num2str(errdB, 3), ' dB | pred err = ', num2str(epdB, 3), ' | applied = ', num2str(b, 5), ' | next = ', num2str(bn, 5), ' | shift = ', num2str(s), ' | state lost = ', num2str(lost), extra]); end
