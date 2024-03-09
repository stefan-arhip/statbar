unit Unit1;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  StdCtrls, ExtCtrls, adCPUUsage, ComCtrls, Registry, Winsock, AMixer,
  TeEngine, Series, TeeProcs, Chart, Spin, VclTee.TeeGDIPlus;

type
  TForm1 = class(TForm)
    Label1: TLabel;
    Timer1: TTimer;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    Label5: TLabel;
    Label6: TLabel;
    Label7: TLabel;
    TrackBar1: TTrackBar;
    Label12: TLabel;
    Label8: TLabel;
    Label9: TLabel;
    Label10: TLabel;
    Label11: TLabel;
    Label13: TLabel;
    Chart1: TChart;
    Series1: TLineSeries;
    Chart2: TChart;
    LineSeries1: TLineSeries;
    Series2: TLineSeries;
    Series3: TLineSeries;
    Label14: TLabel;
    Label15: TLabel;
    TrackBar2: TTrackBar;
    Label16: TLabel;
    Label17: TLabel;
    procedure Timer1Timer(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure TrackBar1Change(Sender: TObject);
    procedure TrackBar2Change(Sender: TObject);
  private
    { Private declarations }
    Setting: Boolean;
  public
    { Public declarations }
  end;

var
  Form1: TForm1;

implementation

{$R *.DFM}

Const
  maxHistory = 99 * 2;

var
  L, R, M: Integer;
  VD, MD: Boolean;
  Stereo: Boolean;
  IsSelect: Boolean;
  RAMHistory, CPUHistory: Array [0 .. maxHistory] Of Extended;
  StartTime, NowTime: TDateTime;
  TheGetCPUSpeed: Extended;

Procedure UpdateHistory(Var History: Array Of Extended; NewValue: Extended);
Var
  i: Integer;
Begin
  For i := 0 To maxHistory - 1 Do
    History[i] := History[i + 1];
  History[maxHistory] := NewValue;
End;

function UpTime: string;
const
  ticksperday: Integer = 1000 * 60 * 60 * 24;
  ticksperhour: Integer = 1000 * 60 * 60;
  ticksperminute: Integer = 1000 * 60;
  tickspersecond: Integer = 1000;
var
  t: LongInt;
  d, h, M, s: Integer;
begin
  t := GetTickCount;
  d := t div ticksperday;
  Dec(t, d * ticksperday);
  h := t div ticksperhour;
  Dec(t, h * ticksperhour);
  M := t div ticksperminute;
  Dec(t, M * ticksperminute);
  s := t div tickspersecond;
  Result := 'Windows Uptime: ' + IntToStr(d) + 'd ' + IntToStr(h) + 'h ' +
    IntToStr(M) + 'm ' + IntToStr(s) + 's ';
end;

function UsedMemory: Extended;
var
  memory: TMemoryStatus; // load  100
begin // total
  memory.dwLength := SizeOf(memory);
  GlobalMemoryStatus(memory);
  Result := (memory.dwTotalPhys - memory.dwAvailPhys) / 1024 / 1024;
end;

function TotalMemory: Extended;
Var
  memory: TMemoryStatus;
Begin
  memory.dwLength := SizeOf(memory);
  GlobalMemoryStatus(memory);
  Result := memory.dwTotalPhys / 1024 / 1024;
End;

function GetCPUSpeed: Extended;
const
  DelayTime = 500;
var
  TimerHi, TimerLo: DWORD;
  PriorityClass, Priority: Integer;
begin
  PriorityClass := GetPriorityClass(GetCurrentProcess);
  Priority := GetThreadPriority(GetCurrentThread);
  SetPriorityClass(GetCurrentProcess, REALTIME_PRIORITY_CLASS);
  SetThreadPriority(GetCurrentThread, THREAD_PRIORITY_TIME_CRITICAL);
  Sleep(10);
  asm
    dw 310Fh
    mov TimerLo, eax
    mov TimerHi, edx
  end;
  Sleep(DelayTime);
  asm
    dw 310Fh
    sub eax, TimerLo
    sbb edx, TimerHi
    mov TimerLo, eax
    mov TimerHi, edx
  end;
  SetThreadPriority(GetCurrentThread, Priority);
  SetPriorityClass(GetCurrentProcess, PriorityClass);
  Result := TimerLo / (1000 * DelayTime);
end;

(* function GetCpuSpeed: string;
  var
  Reg: TRegistry;
  begin
  Reg := TRegistry.Create;
  try
  Reg.RootKey := HKEY_LOCAL_MACHINE;
  if Reg.OpenKey('Hardware\Description\System\CentralProcessor\0', False) then
  begin
  Result := IntToStr(Reg.ReadInteger('~MHz')) + ' MHz';
  Reg.CloseKey;
  end;
  finally
  Reg.Free;
  end;
  end; *)

function IsCapsLockOn: Boolean;
begin
  Result := 0 <> (GetKeyState(VK_CAPITAL) and $01);
end;

Function IsNumLockOn: Boolean;
var
  KeyState: TKeyboardState;
begin
  GetKeyboardState(KeyState);
  Result := (KeyState[VK_NUMLOCK] <> 0);
end;

Function IsScrollLockOn: Boolean;
Begin
  Result := GetKeyState(VK_SCROLL) <> 0;
End;

function IsRunningInsideVirtualPC: Boolean; Assembler;
asm
  push ebp
  mov  ecx, offset @@exception_handler
  mov  ebp, esp
  push ebx
  push ecx
  push dword ptr fs:[0]
  mov  dword ptr fs:[0], esp
  mov  ebx, 0 // flag
  mov  eax, 1 // VPC function number call VPC
  db 00Fh, 03Fh, 007h, 00Bh
  mov eax, dword ptr ss:[esp]
  mov dword ptr fs:[0], eax
  add esp, 8
  test ebx, ebx
  setz al
  lea esp, dword ptr ss:[ebp-4]
  mov ebx, dword ptr ss:[esp]
  mov ebp, dword ptr ss:[esp+4]
  add esp, 8
  jmp @@ret
@@exception_handler:
  mov ecx, [esp+0Ch]
  mov dword ptr [ecx+0A4h], -1 // EBX = -1 -> not running, ebx = 0 -> running
  add dword ptr [ecx+0B8h], 4 // -> skip past the detection code
  xor eax, eax // exception is handled
  ret
@@ret:
end;

Function GiveSystemPowerStatus: String;
var
  SysPowerStatus: TSystemPowerStatus;
begin
  GetSystemPowerStatus(SysPowerStatus);
  if Boolean(SysPowerStatus.ACLineStatus) then
  begin
    Result := 'Running on AC';
  end
  else
    Result := 'Running on battery. ' + Format('Battery power left: %d percent.',
      [SysPowerStatus.BatteryLifePercent]);
end;

function GetOperatingSystem: String;
const { operating system (OS)constants }
  cOsUnknown = -1;
  cOsWin95 = 0;
  cOsWin98 = 1;
  cOsWin98SE = 2;
  cOsWinME = 3;
  cOsWinNT = 4;
  cOsWin2000 = 5;
  cOsXP = 6;
var
  osVerInfo: TOSVersionInfo;
  majorVer, minorVer: Integer;
  Temp: Integer;
begin
  Temp := cOsUnknown;
  { set operating system type flag }
  osVerInfo.dwOSVersionInfoSize := SizeOf(TOSVersionInfo);
  //  More, here:
  //  https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-osversioninfoa
  if GetVersionEx(osVerInfo) then
  begin
    majorVer := osVerInfo.dwMajorVersion;
    minorVer := osVerInfo.dwMinorVersion;
    case osVerInfo.dwPlatformId of
      VER_PLATFORM_WIN32_NT: { Windows NT/2000 }
        begin
          if majorVer <= 4 then
            Temp := cOsWinNT
          else if (majorVer = 5) and (minorVer = 0) then
            Temp := cOsWin2000
          else if (majorVer = 5) and (minorVer = 1) then
            Temp := cOsXP
          else
            Temp := cOsUnknown;
        end;
      VER_PLATFORM_WIN32_WINDOWS: { Windows 9x/ME }
        begin
          if (majorVer = 4) and (minorVer = 0) then
            Temp := cOsWin95
          else if (majorVer = 4) and (minorVer = 10) then
          begin
            if osVerInfo.szCSDVersion[1] = 'A' then
              Temp := cOsWin98SE
            else
              Temp := cOsWin98;
          end
          else if (majorVer = 4) and (minorVer = 90) then
            Temp := cOsWinME
          else
            Temp := cOsUnknown;
        end;
    else
      Temp := cOsUnknown;
    end;
  end
  else
    Temp := cOsUnknown;
  Case Temp Of
    cOsUnknown:
      Result := 'Unknown';
    cOsWin95:
      Result := 'Windows 95';
    cOsWin98:
      Result := 'Windows 98';
    cOsWin98SE:
      Result := 'Windows 98SE';
    cOsWinME:
      Result := 'Windows ME';
    cOsWinNT:
      Result := 'Windows NT';
    cOsWin2000:
      Result := 'Windows 2000';
    cOsXP:
      Result := 'Windows XP';
  End;
end;

function GetLocalIP: string;
type
  TaPInAddr = array [0 .. 10] of PInAddr;
  PaPInAddr = ^TaPInAddr;
var
  phe: PHostEnt;
  pptr: PaPInAddr;
  Buffer: PAnsiChar; // array [0..63] of char;
  i: Integer;
  GInitData: TWSADATA;
begin
  WSAStartup($101, GInitData);
  Result := '';
  GetHostName(Buffer, SizeOf(Buffer));
  phe := GetHostByName(Buffer);
  if phe = nil then
    Exit;
  pptr := PaPInAddr(phe^.h_addr_list);
  i := 0;
  while pptr^[i] <> nil do
  begin
    Result := StrPas(inet_ntoa(pptr^[i]^));
    Inc(i);
  end;
  WSACleanup;
end;

function GetSerialNumber: String;
var
  VolumeSerialNumber: DWORD;
  MaximumComponentLength: DWORD;
  FileSystemFlags: DWORD;
  SerialNumber: string;
begin
  GetVolumeInformation('C:\', nil, 0, @VolumeSerialNumber,
    MaximumComponentLength, FileSystemFlags, nil, 0);
  SerialNumber := IntToHex(HiWord(VolumeSerialNumber), 4) + '-' +
    IntToHex(LoWord(VolumeSerialNumber), 4);
  // SerialNumber:=IntToStr(HiWord(VolumeSerialNumber))+ '-'+IntToStr(LoWord(VolumeSerialNumber));
  Result := SerialNumber;
  // GetVolumeInformation('D:\',nil,0,@VolumeSerialNumber,MaximumComponentLength,FileSystemFlags,nil,0);
  // SerialNumber:=IntToHex(HiWord(VolumeSerialNumber),4)+ '-'+IntToHex(LoWord(VolumeSerialNumber),4);
  // Result:=Result+' - '+SerialNumber;
  // GetVolumeInformation('E:\',nil,0,@VolumeSerialNumber,MaximumComponentLength,FileSystemFlags,nil,0);
  // SerialNumber:=IntToHex(HiWord(VolumeSerialNumber),4)+ '-'+IntToHex(LoWord(VolumeSerialNumber),4);
  // Result:=Result+' - '+SerialNumber;
end;

Function GiveCPUUsage: Extended;
Var
  i: Integer;
  CPUUsage: Extended;
  CPUCount: Integer;
Begin
  CollectCPUData;
  CPUUsage := 0;
  CPUCount := GetCPUCount;
  For i := 1 To CPUCount Do
    CPUUsage := CPUUsage + GetCPUUsage(i - 1) * 100;
  Result := 0;
  If CPUCount <> 0 Then
  Begin
    CPUUsage := CPUUsage / CPUCount;
    Result := CPUUsage;
  End;
  // label4.caption:='CPU Usage: '+FloatToStrF(GetCPUUsage(0)*100,ffFixed,16,2)+' %';
End;

procedure TForm1.Timer1Timer(Sender: TObject);
Var
  Temp: Extended;
  i: Integer;
begin
  Label1.caption := UpTime;
  Temp := UsedMemory;
  Label2.caption := Format('RAM: %4.0f/%4.0f MB', [Temp, TotalMemory]);
  UpdateHistory(RAMHistory, Temp);
  Chart1.Series[0].Clear;
  For i := 0 To maxHistory Do
    Chart1.Series[0].add(RAMHistory[i], '', clRed);
  Temp := GiveCPUUsage;
  Label4.caption := 'CPU Usage: ' + Format('%2.1f', [Temp]) + ' %';
  // FloatToStrF(GiveCPUUsage,ffFixed,16,2)+' %';
  UpdateHistory(CPUHistory, Temp);
  Chart2.Series[0].Clear;
  For i := 0 To maxHistory Do
    Chart2.Series[0].add(CPUHistory[i], '', clBlue);
  If TheGetCPUSpeed <> 0 Then
    Label3.caption := Format('CPU: %4.0f/%4.0f MHz',
      [Temp * TheGetCPUSpeed / 100, TheGetCPUSpeed]);
  If IsCapsLockOn Then
    Label5.caption := 'Caps lock is ON'
  Else
    Label5.caption := 'Caps lock is OFF';
  If IsNumLockOn Then
    Label6.caption := 'Num lock is ON'
  Else
    Label6.caption := 'Num lock is OFF';
  If IsScrollLockOn Then
    Label7.caption := 'Scroll lock is ON'
  Else
    Label7.caption := 'Scroll lock is OFF';
  If IsRunningInsideVirtualPC Then
    Label8.caption := 'Running inside a virtual PC'
  Else
    Label8.caption := 'NOT running inside a virtual PC';
  Label9.caption := GiveSystemPowerStatus;
  Label10.caption := 'Running OS: ' + GetOperatingSystem;
  Label11.caption := 'Local IP is: ' + GetLocalIP;
  // AudioMixer1.GetVolume (0,-1,L,R,M,Stereo,VD,MD,IsSelect);
  Setting := True;
  If TrackBar1.Visible then
    TrackBar1.Position := L;
  Label12.caption := Format('Volume: %2.1f',
    [TrackBar1.Position * 100 / TrackBar1.Max]) + '%';
  Setting := False;
  Label13.caption := 'HDD serial number: ' + GetSerialNumber;
  NowTime := Now();
  Label16.caption := 'Application uptime: ' + FormatDateTime('h',
    NowTime - StartTime) + 'h ' + FormatDateTime('n', NowTime - StartTime) +
    'm ' + FormatDateTime('s', NowTime - StartTime) + 's';
end;

procedure TForm1.FormCreate(Sender: TObject);
Var
  i: Integer;
begin
  For i := 0 To maxHistory Do
  Begin
    RAMHistory[i] := 0;
    CPUHistory[i] := 0;
  End;
  Timer1Timer(Sender);
  // Format('Your CPU speed: %f MHz', [GetCPUSpeed]); //GetCPUSpeed is a Float
  // CollectCPUData;
  // CPUCount:=GetCPUCount;
  TheGetCPUSpeed := GetCPUSpeed;
  Label3.caption := Format('CPU: %.0f', [TheGetCPUSpeed]);
  // AudioMixer1.GetVolume (0,-1,L,R,M,Stereo,VD,MD,IsSelect);
  Setting := True;
  TrackBar1.Visible := not VD;
  If TrackBar1.Visible then
    TrackBar1.Position := L;
  Label12.caption := Format('Volume: %2.1f',
    [TrackBar1.Position * 100 / TrackBar1.Max]) + '%';
  Setting := False;
  // Chart1.Series[1].Clear;
  Chart1.Series[1].add(0, '', clScrollBar);
  Chart1.Series[1].add(TotalMemory, '', clScrollBar); // Chart1.BackColor
  Chart2.Series[1].add(0, '', clScrollBar);
  Chart2.Series[1].add(100, '', clScrollBar); // Chart1.BackColor
  StartTime := Now();
  Label17.caption := 'MAC address: ' + '???';
end;

procedure TForm1.TrackBar1Change(Sender: TObject);
begin
  // If (not Setting) then
  // begin
  // Setting:=True;
  // AudioMixer1.SetVolume (0,-1,TrackBar1.Position,TrackBar1.Position,Integer(False));
  // Label12.Caption:=Format('Volume: %2.1f',[TrackBar1.Position*100/TrackBar1.Max])+'%';
  // Setting:=False;
  // end;
end;

procedure TForm1.TrackBar2Change(Sender: TObject);
begin
  Timer1.Interval := TrackBar2.Position;
end;

end.

(*
  *type
  *  TKeyType = (ktCapsLock, ktNumLock, ktScrollLock);
  *
  *procedure SetLedState(KeyCode: TKeyType; bOn: Boolean);
  *var
  *  KBState: TKeyboardState;
  *  Code: Byte;
  *begin
  *  case KeyCode of
  *    ktScrollLock: Code := VK_SCROLL;
  *    ktCapsLock: Code := VK_CAPITAL;
  *    ktNumLock: Code := VK_NUMLOCK;
  *  end;
  *  GetKeyboardState(KBState);
  *  if (Win32Platform = VER_PLATFORM_WIN32_NT) then
  *  begin
  *    if Boolean(KBState[Code]) <> bOn then
  *    begin
  *      keybd_event(Code,
  *                  MapVirtualKey(Code, 0),
  *                  KEYEVENTF_EXTENDEDKEY,
  *                  0);
  *
  *      keybd_event(Code,
  *                  MapVirtualKey(Code, 0),
  *                  KEYEVENTF_EXTENDEDKEY or KEYEVENTF_KEYUP,
  *                  0);
  *    end;
  *  end
  *  else
  *  begin
  *    KBState[Code] := Ord(bOn);
  *    SetKeyboardState(KBState);
  *  end;
  *end;
  *
  *// Example Call:
  *// Beispielaufruf:
  *
  *procedure TForm1.Button1Click(Sender: TObject);
  *begin
  *  SetLedState(ktCapsLock, True);  // CapsLock on
  *  SetLedState(ktNumLock, True);  // NumLock on
  *  SetLedState(ktScrollLock, True);  // ScrollLock on
  *end;
*)
