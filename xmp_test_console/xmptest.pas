program xmptest;

 // Thanks to Megatron.
 // by Fred vS | fiens@hotmail.com | 2024

{$mode objfpc}{$H+}
{$PACKRECORDS C}

uses
 {$IFDEF UNIX}
  cthreads,
  alsa_min,
 {$ENDIF}
  Classes,
  CustApp,
  libxmp,
 {$IFDEF windows} mmsystem,  windows,{$ENDIF}
  SysUtils;

type

  TxmpConsole = class(TCustomApplication)
  private
    procedure ConsolePlay;
  protected
    procedure doRun; override;
  public
    constructor Create(TheOwner: TComponent); override;
  end;

const
  SampleRate    = 44100;
  Channels      = 2;
  BufferSize    = 8192;
  {$IFDEF windows}
  BitsPerSample = 16;
  BufferCount   = 2;
  {$ENDIF}

{$IFDEF UNIX}
Type
  TalsaThread = class(TThread)
    private
      protected
      procedure Execute; override;
    public
      Constructor Create(CreateSuspended : boolean);
  end;
{$ENDIF}

var
  {$IFDEF windows}  
  waveOut: HWAVEOUT;
  waveHeader: TWaveHdr;
  waveHeaders: array[0..BufferCount-1] of TWaveHdr;
  buffers: array[0..BufferCount - 1] of array[0..BufferSize - 1] of byte;
  currentBuffer: integer;
  {$else}
  alsaThread: TalsaThread;
  pcm: PPsnd_pcm_t;
  {$ENDIF}
  mi: xmp_module_info;
  fi: xmp_frame_info;
  playing: Boolean;
  ctx: xmp_context;
  ordir, thelib: string;
  inct : integer = 0;

 {$IFDEF windows}   
  procedure FillBuffer(bufferIndex: Integer);
    begin
       if xmp_play_buffer(ctx, @buffers[bufferIndex][0], BufferSize, 0) < 0 then
        playing := False;
       xmp_get_frame_info(ctx, fi);
       write(#13 + 'Sec: ' + inttostr(inct) + ' | Row: ' + IntToStr(fi.row));
    end; 
    
   function WaveOutCallback(hwo: HWAVEOUT; uMsg: UINT; dwInstance, dwParam1, dwParam2: DWORD_PTR): DWORD; stdcall;
    begin
      if uMsg = WOM_DONE then
      begin
        FillBuffer(currentBuffer);
        waveOutWrite(hwo, @waveHeaders[currentBuffer], SizeOf(TWaveHdr));
        currentBuffer := (currentBuffer + 1) mod BufferCount;
      end;
      Result := 0;
    end;
     
    procedure InitAudio;
    var
      wFormat: TWaveFormatEx;
      i : integer;
    begin
      wFormat.wFormatTag := WAVE_FORMAT_PCM;
      wFormat.nChannels := Channels;
      wFormat.nSamplesPerSec := SampleRate;
      wFormat.wBitsPerSample := BitsPerSample;
      wFormat.nBlockAlign := (wFormat.wBitsPerSample * wFormat.nChannels) div 8;
      wFormat.nAvgBytesPerSec := wFormat.nSamplesPerSec * wFormat.nBlockAlign;
       wFormat.cbSize := 0;
     
       if waveOutOpen(@waveOut, WAVE_MAPPER, @wFormat, QWORD(@WaveOutCallback), 0, CALLBACK_FUNCTION) <> MMSYSERR_NOERROR then
        raise Exception.Create('Error WaveOutOpen');
     
      for i := 0 to BufferCount - 1 do
      begin
        ZeroMemory(@waveHeaders[i], SizeOf(TWaveHdr));
        waveHeaders[i].lpData := @buffers[i][0];
        waveHeaders[i].dwBufferLength := BufferSize;
        waveHeaders[i].dwFlags := 0;
        waveHeaders[i].dwLoops := 0;
        waveOutPrepareHeader(waveOut, @waveHeaders[i], SizeOf(TWaveHdr));
      end;
     
      currentBuffer := 0;
      for i := 0 to BufferCount - 1 do
      begin
        FillBuffer(i);
        waveOutWrite(waveOut, @waveHeaders[i], SizeOf(TWaveHdr));
      end;
     
    end;
     
    procedure CloseAudio;
    begin
      waveOutUnprepareHeader(waveOut, @waveHeader, SizeOf(TWaveHdr));
      waveOutClose(waveOut);
    end;

 {$ELSE}// Unix

  procedure InitAudio;
  var
    buffer: array[0..BufferSize - 1] of byte;
    frames: snd_pcm_sframes_t;
  begin
    as_Load();       // load the library

    if snd_pcm_open(@pcm, @device[1], SND_PCM_STREAM_PLAYBACK, 0) = 0 then
      if snd_pcm_set_params(pcm, SND_PCM_FORMAT_S16,
        SND_PCM_ACCESS_RW_INTERLEAVED,
        Channels,                        // number of channels
        SampleRate,                      // sample rate (Hz)
        1,                               // resampling on/off
        500000) = 0 then            // latency (us)
      begin

        xmp_get_module_info(ctx, mi);
        xmp_get_frame_info(ctx, fi);

        writeln('bmp: ' + IntToStr(fi.bpm));
        writeln('speed: ' + IntToStr(fi.speed));
        writeln('position: ' + IntToStr(fi.pos));
        writeln('pattern: ' + IntToStr(fi.pattern));
        writeln('row: ' + IntToStr(fi.row));
        writeln('module channels: ' + IntToStr(mi.module^.chn));
        writeln('used channels: ' + IntToStr(fi.virt_used));
        writeln('volume: ' + IntToStr(fi.volume));
        writeln('title: ' + string(mi.module^.Name));
        writeln('type: ' + string(mi.module^.typ));
        writeln();

        playing := True;

        while playing do
        begin
           xmp_get_frame_info(ctx, fi);
 
          write(#13 + 'Sec: ' + inttostr(inct) + ' | Row: ' + IntToStr(fi.row));
            
          if xmp_play_buffer(ctx, @buffer, BufferSize, 0) < 0 then
            playing := False;
          frames    := snd_pcm_writei(pcm, @buffer[0], BufferSize div 4);
          if frames < 0 then
            frames := snd_pcm_recover(pcm, frames, 0); // try to recover from any error
          if frames < 0 then
            break;
        end;
      end;
  end;

  procedure CloseAudio;
  begin
    alsaThread.terminate;
    snd_pcm_drain(pcm);                      // drain any remaining samples
    snd_pcm_close(pcm);
    as_unLoad();
  end;

  constructor TalsaThread.Create(CreateSuspended: Boolean);
  begin
    inherited Create(CreateSuspended);
    FreeOnTerminate := True;
  end;

  procedure TalsaThread.Execute;
  begin
    InitAudio;
  end;

{$ENDIF}// End Unix

  constructor TxmpConsole.Create(TheOwner: TComponent);
  begin
    inherited Create(TheOwner);
    StopOnException := True;
  end;


  procedure TxmpConsole.ConsolePlay;
  begin
    ordir := IncludeTrailingBackslash(ExtractFilePath(ParamStr(0)));

{$IFDEF windows}
    thelib := 'libxmp.dll';
{$Else}
    thelib := 'libxmp.so.4.6.0';
{$ENDIF}

    if xmp_Load(ordir + thelib) then
    begin
      writeln('LoadLib OK');

      ctx     := xmp_create_context();
      playing := True;
     {$IFDEF windows}
      InitAudio;
     {$ENDIF}
      ordir   := ordir + 'example.it';
      if xmp_load_module(ctx, PChar(ordir)) <> 0 then
      begin
        writeln('Load module error.');
        Exit;
      end;
      xmp_start_player(ctx, SampleRate, 0);
      playing := True;

     {$IFDEF windows}  
    xmp_get_module_info(ctx, mi);
    xmp_get_frame_info(ctx, fi);
    writeln();
    writeln('bmp: ' + IntToStr(fi.bpm));
    writeln('speed: ' + IntToStr(fi.speed));
    writeln('position: ' + IntToStr(fi.pos));
    writeln('pattern: ' + IntToStr(fi.pattern));
    writeln('row: ' + IntToStr(fi.row));
    writeln('module channels: ' + IntToStr(mi.module^.chn));
    writeln('used channels: ' + IntToStr(fi.virt_used));
    writeln('volume: ' + IntToStr(fi.volume));
    writeln('title: ' + string(mi.module^.Name));
    writeln('type: ' + string(mi.module^.typ));
    {$ENDIF}

     {$IFDEF unix}
      alsaThread := TalsaThread.Create(True);
      alsaThread.Start;
     {$ENDIF}

      writeln();
      writeln('Playing during 30 seconds...');
      writeln();
      sleep(1000);
      while inct < 30 do
      begin
       inc(inct);
       sleep(1000);
      end;
      
      writeln();
      writeln();
      writeln('Stop playing after 30 seconds...');
      writeln();
      writeln('Bye!');
    end
    else
      writeln('LoadLib NOT OK');
  end;

  procedure TxmpConsole.doRun;
  begin
    ConsolePlay;
    CloseAudio;
    playing := False;
    xmp_end_player(ctx);
    xmp_release_module(ctx);
    xmp_free_context(ctx);
    xmp_unload();
    Terminate;
  end;

var
  Application: TxmpConsole;

begin
  Application       := TxmpConsole.Create(nil);
  Application.Title := 'Console xmp';
  Application.Run;
  Application.Free;
end.

