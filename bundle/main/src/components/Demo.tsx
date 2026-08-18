import type { ReactNode } from '@lynx-js/react';

/** Card wrapper used by every demo page: a title, an optional description and content. */
export function DemoCard(props: {
  title: string;
  desc?: string;
  children?: ReactNode;
}) {
  return (
    <view className="DemoCard">
      <text className="DemoCard__title">{props.title}</text>
      {props.desc ? <text className="DemoCard__desc">{props.desc}</text> : null}
      {props.children}
    </view>
  );
}

/** WeChat-style demo button: green primary, white default. */
export function DemoButton(props: {
  label: string;
  onTap: () => void;
  primary?: boolean;
  disabled?: boolean;
}) {
  const classes = [
    'DemoButton',
    props.primary ? 'DemoButton--primary' : '',
    props.disabled ? 'DemoButton--disabled' : '',
  ]
    .filter((name) => name.length > 0)
    .join(' ');
  const labelClasses = [
    'DemoButton__label',
    props.primary ? 'DemoButton__label--primary' : '',
  ]
    .filter((name) => name.length > 0)
    .join(' ');
  return (
    <view
      className={classes}
      bindtap={props.disabled ? undefined : props.onTap}
    >
      <text className={labelClasses}>{props.label}</text>
    </view>
  );
}

/** Result area showing the latest outcome of a demo call. */
export function ResultLine(props: {
  text: string | null;
  placeholder: string;
}) {
  return (
    <view className="ResultLine">
      <text className="ResultLine__text">
        {props.text ?? props.placeholder}
      </text>
    </view>
  );
}

/** Monospace API name header, mirroring the WeChat demo pages. */
export function ApiName(props: { name: string }) {
  return (
    <view className="ApiName">
      <text className="ApiName__text">{props.name}</text>
      <view className="ApiName__underline" />
    </view>
  );
}
